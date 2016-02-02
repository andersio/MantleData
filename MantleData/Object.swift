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

	final public func producerFor<Value: CocoaBridgeable where Value.Inner: CocoaBridgeable>(keyPath: String, type: Value.Type? = nil) -> SignalProducer<Value, NoError> {
		return isFaulted.producer
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

/// ObjectType provides a set of default implementations of object graph manipulation to NSManagedObject and its subclasses.
public protocol ObjectType: class {
	init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?)
}

extension Object: ObjectType { }

/// Instance methods
extension ObjectType where Self: Object {
	private typealias _Self = Self

	final public var isChangedProducer: SignalProducer<Self, NoError> {
		return isFaulted.producer
			.filter { !$0 }
			.flatMap(.Latest) { [unowned self] _ -> SignalProducer<_Self, NoError> in
				let (producer, observer) = SignalProducer<_Self, NoError>.buffer(1)

				let kvoController = AttributeKVOController(object: self,
					keyPath: "isChanged",
					newValueObserver: { _ in
						observer.sendNext(self)
					})

				let disposable = self.isFaulted.producer
					.filter { $0 }
					.start { _ in
						observer.sendCompleted()
						kvoController
				}

				producer.startWithCompleted { disposable.dispose() }

				return producer
		}
	}

	final public func propertyFor<Value: CocoaBridgeable where Value.Inner: CocoaBridgeable>(keyPath: String) -> AnyProperty<Value> {
		return AnyProperty(initialValue: Value(cocoaValue: valueForKeyPath(keyPath)),
			producer: producerFor(keyPath))
	}

  final public var objectContext: ObjectContext {
    if let context = managedObjectContext as? ObjectContext {
      return context
    }
    
    precondition(managedObjectContext != nil, "The object context is deallocated.")
    preconditionFailure("The object is not from a MantleData object context.")
  }

	final public func with(context: ObjectContext) -> Self {
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

  /// Insert a new object.
  /// - Parameter context: The context the object to be inserted into. If unspecified, it uses the context inferer.
  /// - Returns: The resulting object.
	final public static func with(context: ObjectContext) -> FetchRequestProducer<Self> {
		return FetchRequestProducer(context: context)
	}
}

public struct FetchRequestProducer<T: Object where T: ObjectType> {
	let context: ObjectContext

  public func new() -> T {
    guard let entityDescription = NSEntityDescription.entityForName(T.entityName, inManagedObjectContext: context) else {
      preconditionFailure("Failed to create entity description of entity `\(T.entityName)`.")
    }
    return T(entity: entityDescription, insertIntoManagedObjectContext: context)
  }
  
  public func find(ID: NSManagedObjectID) -> T {
    assert(ID.entity.name == T.entityName, "Entity does not match with the ID.")
    return try! context.existingObjectWithID(ID) as! T
  }

  public func find(IDs: [NSManagedObjectID]) -> [T] {
    var objects = [T]()
    for ID in IDs {
      assert(ID.entity.name == T.entityName, "Entity does not match with the ID.")
      objects.append(try! context.existingObjectWithID(ID) as! T)
    }
    return objects
  }
  
	public var all: ResultProducer<T> {
    return filter(nil)
  }

  public func filter(predicate: NSPredicate?) -> ResultProducer<T> {
    let request = NSFetchRequest()
    request.predicate = predicate
		return ResultProducer(entityName: T.entityName, fetchRequest: request, context: context)
  }
  
  public func filter(formatString: String, _ args: AnyObject...) -> ResultProducer<T> {
    return filter(formatString, args: args)
  }
  
  public func filter(formatString: String, args: [AnyObject]) -> ResultProducer<T> {
    let request = NSFetchRequest()
    request.predicate = NSPredicate(format: formatString, argumentArray: args)
    
    return ResultProducer(entityName: T.entityName, fetchRequest: request, context: context)
  }
}