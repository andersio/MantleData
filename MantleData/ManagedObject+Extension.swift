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
	public var id: ManagedObjectID<Self> {
		return ManagedObjectID(object: self)
	}

	/// Return a producer which emits the current and subsequent values for the supplied key path.
	/// A fault would be fired when the producer is started.
	/// - Parameter keyPath: The key path to be observed.
	/// - Important: You should avoid using it in any overrided methods of `Object`
	///              if the producer might outlive the object.
	final public func producer<Value: CocoaBridgeable>(forKeyPath keyPath: String, type: Value.Type? = nil) -> SignalProducer<Value, NoError> where Value._Inner: CocoaBridgeable {
		return SignalProducer { [weak self] observer, disposable in
			guard let strongSelf = self else {
				observer.sendInterrupted()
				return
			}

			// Fire fault.
			strongSelf.willAccessValue(forKey: nil)
			defer { strongSelf.didAccessValue(forKey: nil) }

			disposable += strongSelf.values(forKeyPath: keyPath)
				.startWithNext { [weak self] value in
					if let strongSelf = self, strongSelf.faultingState == 0 && !strongSelf.isDeleted {
						observer.sendNext(Value(cocoaValue: value))
					}
				}
		}
	}

	final public func property<Value: CocoaBridgeable>(forKeyPath keyPath: String, type: Value.Type? = nil) -> ManagedObjectProperty<Value> where Value._Inner: CocoaBridgeable {
		return ManagedObjectProperty(keyPath: keyPath, for: self)
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

	final public static func query(_ context: NSManagedObjectContext) -> ObjectQuery<Self> {
		return ObjectQuery(context: context)
	}

	public func finding(ID: NSManagedObjectID, in context: NSManagedObjectContext) -> Self {
		assert(ID.entity.name == String(describing: Self.self), "Entity does not match with the ID.")
		return context.object(with: ID) as! Self
	}

	public func finding(IDs: [NSManagedObjectID], in context: NSManagedObjectContext) -> [Self] {
		var objects = [Self]()
		for ID in IDs {
			assert(ID.entity.name == String(describing: Self.self), "Entity does not match with the ID.")
			objects.append(context.object(with: ID) as! Self)
		}
		return objects
	}
}

final public class ManagedObjectProperty<_Value: CocoaBridgeable>: MutablePropertyProtocol where _Value._Inner: CocoaBridgeable {
	public typealias Value = _Value
	private let object: NSManagedObject
	private let keyPath: String

	public init(keyPath: String, for object: NSManagedObject) {
		self.keyPath = keyPath
		self.object = object
	}

	public var value: Value {
		get { return Value(cocoaValue: object.value(forKeyPath: keyPath)) }
		set { object.setValue(newValue.cocoaValue, forKey: keyPath) }
	}

	public var producer: SignalProducer<Value, NoError> {
		return object.producer(forKeyPath: keyPath)
	}

	public var signal: Signal<Value, NoError> {
		var signal: Signal<Value, NoError>!
		producer.startWithSignal { startedSignal, _ in signal = startedSignal }
		return signal
	}
}
