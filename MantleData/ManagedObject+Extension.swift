//
//  ManagedObject+Extension.swift
//  MantleData
//
//  Created by Anders on 9/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveCocoa

public protocol ManagedObjectProtocol {}
extension NSManagedObject: ManagedObjectProtocol {}

extension ManagedObjectProtocol where Self: NSManagedObject {
	public var typedObjectID: ManagedObjectID<Self> {
		return ManagedObjectID(object: self)
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
			strongSelf.willAccessValue(forKey: nil)
			defer { strongSelf.didAccessValue(forKey: nil) }

			let proxyBox = Atomic<KVOProxy?>(KVOProxy(keyPath: keyPath) { [weak strongSelf] value in
				if let strongSelf = strongSelf where strongSelf.faultingState == 0 && !strongSelf.isDeleted {
					observer.sendNext(Value(cocoaValue: value))
				}
			})

			proxyBox.value!.attach(to: strongSelf)

			let deinitDisposable = strongSelf.willDeinitProducer
				.startWithNext { [unowned strongSelf, weak proxyBox] in
					if let proxy = proxyBox?.swap(nil) {
						proxy.detach(from: strongSelf)
						observer.sendCompleted()
					}
				}

			disposable += ActionDisposable { [weak self] in
				if let strongSelf = self {
					if let proxy = proxyBox.swap(nil) {
						proxy.detach(from: strongSelf)
						observer.sendCompleted()
						deinitDisposable.dispose()
					}
				}
			}
		}
	}

	final public func converted(for context: NSManagedObjectContext) -> Self {
		if context === managedObjectContext {
			return self
		} else {
			do {
				return try context.existingObject(with: objectID) as! Self
			} catch {
				return context.object(with: objectID) as! Self
			}
		}
	}

	final public static func collection(in context: NSManagedObjectContext) -> LazyObjectCollection<Self> {
		return LazyObjectCollection(in: context)
	}

	final public static func make(in context: NSManagedObjectContext) -> Self {
		guard let entityDescription = NSEntityDescription.entityForName(String(Self), inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(String(Self))`.")
		}
		return Self(entity: entityDescription, insertIntoManagedObjectContext: context)
	}

	public func finding(ID ID: NSManagedObjectID, in context: NSManagedObjectContext) -> Self {
		assert(ID.entity.name == String(Self), "Entity does not match with the ID.")
		return context.object(with: ID) as! Self
	}

	public func finding(IDs: [NSManagedObjectID], in context: NSManagedObjectContext) -> [Self] {
		var objects = [Self]()
		for ID in IDs {
			assert(ID.entity.name == String(Self), "Entity does not match with the ID.")
			objects.append(context.object(with: ID) as! Self)
		}
		return objects
	}
}

private var kvoProxyContext = UnsafeMutablePointer<Void>.alloc(1)

final private class KVOProxy: NSObject {
	let action: (AnyObject?) -> Void
	let keyPath: String

	init(keyPath: String, action: (AnyObject?) -> Void) {
		self.action = action
		self.keyPath = keyPath
		super.init()
	}

	func attach(to object: NSObject) {
		object.addObserver(self, forKeyPath: keyPath, options: [.initial, .new], context: kvoProxyContext)
	}

	func detach(from object: NSObject) {
		object.removeObserver(self, forKeyPath: keyPath, context: kvoProxyContext)
	}

	override func observeValue(forKeyPath keyPath: String?, of object: AnyObject?, change: [NSKeyValueChangeKey : AnyObject]?, context: UnsafeMutablePointer<Void>?) {
		if context == kvoProxyContext {
			action(change![NSKeyValueChangeKey.newKey])
		}
	}
}
