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
  final private var _isFaulted = MutableProperty<Bool>(true)
  final private(set) public lazy var isFaulted: AnyProperty<Bool> = AnyProperty(self._isFaulted)

	required override public init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?) {
		super.init(entity: entity, insertIntoManagedObjectContext: context)
	}

  final public override func awakeFromInsert() {
    super.awakeFromInsert()
    _isFaulted.value = false
  }
  
  final public override func awakeFromFetch() {
    super.awakeFromFetch()
    _isFaulted.value = false
  }

  final public override func prepareForDeletion() {
    super.prepareForDeletion()
    _isFaulted.value = true
  }
  
  final public override func willTurnIntoFault() {
    super.willTurnIntoFault()
    _isFaulted.value = true
  }

	/// Important: The returned producer will fire a fault when started.
	final public func producer<Value: CocoaBridgeable where Value.Inner: CocoaBridgeable>(forKeyPath keyPath: String, type: Value.Type? = nil) -> SignalProducer<Value, NoError> {
		return _isFaulted.producer
			.filter { !$0 }
			.flatMap(.Latest) { [unowned self] _ -> SignalProducer<Value, NoError> in
				let (producer, observer) = SignalProducer<Value, NoError>.buffer(1)

				let kvoController = AttributeKVOController(object: self,
					keyPath: keyPath,
					newValueObserver: {
						observer.sendNext(Value(cocoaValue: $0))
					})

				let disposable = self.isFaulted.producer
					.filter { $0 }
					.start { _ in
						observer.sendCompleted()
						kvoController
					}

				producer.startWithCompleted { [weak disposable] in
					disposable?.dispose()
				}
				
				return producer
			}
			.on(started: {
				self.willAccessValueForKey(nil)
				self.didAccessValueForKey(nil)
			})
	}

	private dynamic var isChanged: Bool {
		return true
	}

	var keyPathsForValuesAffectingIsChanged: Set<String> {
		return Set(entity.attributesByName.keys)
	}
}

final private class AttributeKVOController: NSObject {
	weak var object: NSObject?
	let keyPath: String
	let newValueObserver: AnyObject? -> Void

	init(object: NSObject, keyPath: String, newValueObserver: AnyObject? -> Void) {
		self.object = object
		self.keyPath = keyPath
		self.newValueObserver = newValueObserver
		super.init()

		self.object?.addObserver(self, forKeyPath: keyPath, options: [.Initial, .New], context: nil)
	}

	override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
		if object === self.object {
			newValueObserver(change![NSKeyValueChangeNewKey])
		}
	}

	deinit {
		object?.removeObserver(self, forKeyPath: keyPath, context: nil)
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

	final public func property<Value: CocoaBridgeable where Value.Inner: CocoaBridgeable>(forKeyPath keyPath: String) -> AnyProperty<Value> {
		return AnyProperty(initialValue: Value(cocoaValue: valueForKeyPath(keyPath)),
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

	final public static func with(context: ObjectContext) -> FetchRequestBuilder<Self> {
		return FetchRequestBuilder(context: context)
	}
}