//
//  ReactiveCocoa+Additions.swift
//  MantleData
//
//  Created by Anders on 24/4/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift

extension Observer {
	public func sendCompleted(with finalValue: Value) {
		send(value: finalValue)
		sendCompleted()
	}
}

public class AnyMutableProperty<Value>: MutablePropertyProtocol {
	private let _value: () -> Value
	private let _valueSetter: (Value) -> Void
	private let _lifetime: () -> Lifetime
	private let _producer: () -> SignalProducer<Value, NoError>
	private let _signal: () -> Signal<Value, NoError>

	public var value: Value {
		get { return _value() }
		set { _valueSetter(newValue) }
	}

	public var producer: SignalProducer<Value, NoError> {
		return _producer()
	}

	public var signal: Signal<Value, NoError> {
		return _signal()
	}

	public var lifetime: Lifetime {
		return _lifetime()
	}

	/// Initializes a property as a read-only view of the given property.
	public init<P: MutablePropertyProtocol>(_ property: P) where P.Value == Value {
		_value = { property.value }
		_valueSetter = { property.value = $0 }
		_producer = { property.producer }
		_signal = { property.signal }
		_lifetime = { property.lifetime }
	}
}
