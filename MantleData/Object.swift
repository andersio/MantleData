//
//  Object.swift
//  MantleData
//
//  Created by Anders on 9/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveCocoa

public class Object: NSManagedObject {
	private let (deinitSignal, deinitObserver) = Signal<Object, NoError>.pipe()

	required override public init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?) {
		super.init(entity: entity, insertIntoManagedObjectContext: context)
	}

	deinit {
		deinitObserver.sendNext(self)
		deinitObserver.sendCompleted()
	}

	/// Return a producer which emits the current and subsequent values for the supplied key path.
	/// A fault would be fired when the producer is started.
	/// - Parameter keyPath: The key path to be observed.
	/// - Important: You should avoid using it in any overrided methods of `Object`
	///              if the producer might outlive the object.
	final public func producer<Value: CocoaBridgeable where Value._Inner: CocoaBridgeable>(forKeyPath keyPath: String, type: Value.Type? = nil) -> SignalProducer<Value, NoError> {
		return SignalProducer { [weak self] observer, disposable in
			guard let strongSelf = self else {
				observer.sendInterrupted()
				return
			}

			// Fire fault.
			strongSelf.willAccessValueForKey(nil)
			defer { strongSelf.didAccessValueForKey(nil) }

			let proxyBox = Atomic<KVOProxy?>(KVOProxy(keyPath: keyPath) { [weak strongSelf] value in
				if let strongSelf = strongSelf where !strongSelf.fault {
					observer.sendNext(Value(cocoaValue: value))
				}
			})

			proxyBox.value!.attach(to: strongSelf)

			func disposeProxy(with referenceToSelf: Object) {
				if let proxy = proxyBox.swap(nil) {
					proxy.detach(from: referenceToSelf)
					observer.sendCompleted()
				}
			}

			disposable += strongSelf.deinitSignal.observeNext { deinitializingSelf in
					disposeProxy(with: deinitializingSelf)
				}

			disposable += ActionDisposable { [weak self] in
				if let strongSelf = self {
					disposeProxy(with: strongSelf)
				}
			}
		}
	}
}

private var kvoProxyContext = UnsafeMutablePointer<Void>.alloc(1)

final private class KVOProxy: NSObject {
	let action: AnyObject? -> Void
	let keyPath: String

	init(keyPath: String, action: AnyObject? -> Void) {
		self.action = action
		self.keyPath = keyPath
		super.init()
	}

	func attach(to object: NSObject) {
		object.addObserver(self, forKeyPath: keyPath, options: [.Initial, .New], context: kvoProxyContext)
	}

	func detach(from object: NSObject) {
		object.removeObserver(self, forKeyPath: keyPath, context: kvoProxyContext)
	}

	override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
		if context == kvoProxyContext {
			action(change![NSKeyValueChangeNewKey])
		}
	}
}

/// ObjectType provides a set of default implementations of object graph
/// manipulation to NSManagedObject and its subclasses.
public protocol ObjectType: class {
	init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?)
}

extension Object: ObjectType { }

/// Instance methods
extension ObjectType where Self: Object {
	private typealias _Self = Self

	final public func property<Value: CocoaBridgeable where Value._Inner: CocoaBridgeable>(forKeyPath keyPath: String) -> AnyProperty<Value> {
		return AnyProperty<Value>(initialValue: Value(cocoaValue: valueForKeyPath(keyPath)),
		                   producer: producer(forKeyPath: keyPath))
	}

	final public var objectContext: ObjectContext {
		if let context = managedObjectContext as? ObjectContext {
			return context
		}

		precondition(managedObjectContext != nil, "The object context is deallocated.")
		preconditionFailure("The object is not from a MantleData object context.")
	}

	final public func converted(for context: ObjectContext) -> Self {
		if context === managedObjectContext {
			return self
		} else {
			do {
				return try context.existingObjectWithID(objectID) as! Self
			} catch {
				return context.objectWithID(objectID) as! Self
			}
		}
	}

	final public func save() throws {
		try objectContext.save()
	}

	final public static var entityName: String {
		return String(Self)
	}


	final public static func with(context: ObjectContext,
	                              @noescape action: (inout using: FetchRequestBuilder) throws -> Void) rethrows -> ResultProducer<Self> {
		var builder = FetchRequestBuilder(entity: entityName, in: context)
		try action(using: &builder)
		return ResultProducer(builder: builder)
	}

	final public static func make(in context: ObjectContext) -> Self {
		guard let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(entityName)`.")
		}
		return Self(entity: entityDescription, insertIntoManagedObjectContext: context)
	}

	public func finding(for ID: NSManagedObjectID, in context: ObjectContext) -> Self {
		assert(ID.entity.name == Self.entityName, "Entity does not match with the ID.")
		return try! context.existingObjectWithID(ID) as! Self
	}

	public func finding(for IDs: [NSManagedObjectID], in context: ObjectContext) -> [Self] {
		var objects = [Self]()
		for ID in IDs {
			assert(ID.entity.name == Self.entityName, "Entity does not match with the ID.")
			objects.append(try! context.existingObjectWithID(ID) as! Self)
		}
		return objects
	}
}