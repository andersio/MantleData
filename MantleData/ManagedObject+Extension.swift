//
//  ManagedObject+Extension.swift
//  MantleData
//
//  Created by Anders on 9/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveSwift
import ReactiveCocoa
import enum Result.NoError

public protocol ManagedObjectProtocol: class {}

extension NSManagedObject: ManagedObjectProtocol {
	public static func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
		let entity = NSEntityDescription.entity(forEntityName: String(describing: self),
		                                        in: context)
		return entity!
	}

	/// Return a producer which emits the current and subsequent values for the supplied key path.
	/// A fault would be fired when the producer is started.
	///
	/// - important: You should avoid using it in any overrided methods of `Object`
	///              if the producer might outlive the object.
	///
	/// - parameters:
	///   - keyPath: The key path to be observed.
	public func producer<Value>(forKeyPath keyPath: String, type: Value?.Type? = nil) -> SignalProducer<Value?, NoError> {
		return producer(forKeyPath: keyPath) { $0 as! Value? }
	}

	/// Return a producer which emits the current and subsequent values for the supplied key path.
	/// A fault would be fired when the producer is started.
	///
	/// - important: You should avoid using it in any overrided methods of `Object`
	///              if the producer might outlive the object.
	///
	/// - parameters:
	///   - keyPath: The key path to be observed.
	public func producer<Value>(forKeyPath keyPath: String, type: Value.Type? = nil) -> SignalProducer<Value, NoError> {
		return producer(forKeyPath: keyPath) { $0 as! Value }
	}

	private func producer<Value>(forKeyPath keyPath: String, extract: @escaping (Any?) -> Value) -> SignalProducer<Value, NoError> {
		return SignalProducer { [weak self] observer, disposable in
			guard let strongSelf = self else {
				observer.sendInterrupted()
				return
			}

			// Fire fault.
			strongSelf.willAccessValue(forKey: nil)
			defer { strongSelf.didAccessValue(forKey: nil) }

			disposable += strongSelf.reactive
				.values(forKeyPath: keyPath)
				.startWithValues { [weak self] value in
					if let strongSelf = self, strongSelf.faultingState == 0 && !strongSelf.isDeleted {
						observer.send(value: extract(value))
					}
			}
		}
	}


	public func property<Value>(forKeyPath keyPath: String, type: Value.Type? = nil) -> ObjectProperty<Value> {
		return ObjectProperty(keyPath: keyPath, for: self)
	}
}

extension ManagedObjectProtocol where Self: NSManagedObject {
	public static func fetchRequest(in context: NSManagedObjectContext) -> NSFetchRequest<Self> {
		let fetchRequest = NSFetchRequest<Self>()
		fetchRequest.entity = Self.entity(in: context)
		return fetchRequest
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

	public static func query(_ context: NSManagedObjectContext) -> ObjectQuery<Self> {
		return ObjectQuery(in: context)
	}

	public static func find(ID: ManagedObjectID<Self>, in context: NSManagedObjectContext) -> Self {
		return context.object(with: ID.id) as! Self
	}

	public var id: ManagedObjectID<Self> {
		return ManagedObjectID(object: self)
	}

	public func equivalent(in context: NSManagedObjectContext) -> Self {
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
}

public final class ObjectProperty<Value>: MutablePropertyProtocol {
	private let object: NSManagedObject
	private let keyPath: String

	fileprivate init(keyPath: String, for object: NSManagedObject) {
		self.keyPath = keyPath
		self.object = object
	}

	public var value: Value {
		get { return object.value(forKeyPath: keyPath) as! Value }
		set { object.setValue(newValue, forKey: keyPath) }
	}

	public var lifetime: Lifetime {
		return object.reactive.lifetime
	}

	public var producer: SignalProducer<Value, NoError> {
		return object.producer(forKeyPath: keyPath)
	}

	public var signal: Signal<Value, NoError> {
		var signal: Signal<Value, NoError>!
		producer.startWithSignal { startedSignal, _ in signal = startedSignal }
		return signal
	}

	public static func <~ <S: SignalProtocol>(target: ObjectProperty, source: S) -> Disposable? where S.Value == Value, S.Error == NoError {
		return source
			.take(during: target.lifetime)
			.observeValues { [weak object = target.object, keyPath = target.keyPath] value in
				object?.setValue(value, forKey: keyPath)
			}
	}
}
