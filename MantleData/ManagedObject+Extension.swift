//
//  ManagedObject+Extension.swift
//  MantleData
//
//  Created by Anders on 9/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveSwift

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
		return producer(forKeyPath: keyPath, extract: Bridgeable<Value>.extract)
	}

	final public func producer<Value>(forKeyPath keyPath: String, extract: @escaping (Any?) -> Value) -> SignalProducer<Value, NoError> {
		return SignalProducer { [weak self] observer, disposable in
			guard let strongSelf = self else {
				observer.sendInterrupted()
				return
			}

			// Fire fault.
			strongSelf.willAccessValue(forKey: nil)
			defer { strongSelf.didAccessValue(forKey: nil) }

			disposable += strongSelf.values(forKeyPath: keyPath)
				.startWithValues { [weak self] value in
					if let strongSelf = self, strongSelf.faultingState == 0 && !strongSelf.isDeleted {
						observer.send(value: extract(value))
					}
				}
		}
	}

	final public func property<Value: CocoaBridgeable>(forKeyPath keyPath: String, type: Value.Type? = nil) -> ObjectProperty<Value> where Value._Inner: CocoaBridgeable {
		return ObjectProperty(keyPath: keyPath, for: self, representation: Bridgeable<Value>.self)
	}

	final public func property<Value: AnyObject>(forKeyPath keyPath: String, type: Value?.Type? = nil) -> ObjectProperty<Value?> {
		return ObjectProperty(keyPath: keyPath, for: self, representation: Exact<Value>.self)
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

	public static func find(ID: ManagedObjectID<Self>, in context: NSManagedObjectContext) -> Self {
		return context.object(with: ID.id) as! Self
	}

	public static func find(ID: NSManagedObjectID, in context: NSManagedObjectContext) -> Self {
		assert(ID.entity.name == String(describing: Self.self), "Entity does not match with the ID.")
		return context.object(with: ID) as! Self
	}

	public static func find(IDs: [NSManagedObjectID], in context: NSManagedObjectContext) -> [Self] {
		var objects = [Self]()
		for ID in IDs {
			assert(ID.entity.name == String(describing: Self.self), "Entity does not match with the ID.")
			objects.append(context.object(with: ID) as! Self)
		}
		return objects
	}
}

public protocol ObjectPropertyRepresentable {
	associatedtype Value

	static func extract(from value: Any?) -> Value
	static func represent(_ value: Value) -> Any?
}

public enum Exact<Object: AnyObject>: ObjectPropertyRepresentable {
	public static func extract(from value: Any?) -> Object? {
		return value as! Object?
	}

	public static func represent(_ value: Object?) -> Any? {
		return value
	}
}

public enum Bridgeable<Value: CocoaBridgeable>: ObjectPropertyRepresentable where Value._Inner: CocoaBridgeable {
	public static func extract(from value: Any?) -> Value {
		return Value(cocoaValue: value)
	}

	public static func represent(_ value: Value) -> Any? {
		return value.cocoaValue
	}
}

final public class ObjectProperty<Value>: MutablePropertyProtocol {
	private let object: NSManagedObject
	private let keyPath: String

	private let extract: (Any?) -> Value
	private let represent: (Value) -> Any?

	public init<Representation: ObjectPropertyRepresentable>(keyPath: String, for object: NSManagedObject, representation: Representation.Type) where Representation.Value == Value {
		self.keyPath = keyPath
		self.object = object
		self.extract = representation.extract(from:)
		self.represent = representation.represent
	}

	public var value: Value {
		get { return extract(object.value(forKeyPath: keyPath)) }
		set { object.setValue(represent(newValue), forKey: keyPath) }
	}

	public var producer: SignalProducer<Value, NoError> {
		return object.producer(forKeyPath: keyPath, extract: extract)
	}

	/// The lifetime of `self`. The binding operators use this to determine when
	/// the binding should be teared down.
	public var lifetime: Lifetime {
		return object.rac.lifetime
	}

	public var signal: Signal<Value, NoError> {
		var signal: Signal<Value, NoError>!
		producer.startWithSignal { startedSignal, _ in signal = startedSignal }
		return signal
	}
}
