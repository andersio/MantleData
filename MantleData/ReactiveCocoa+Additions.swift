//
//  ReactiveCocoa+Additions.swift
//  MantleData
//
//  Created by Anders on 24/4/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

extension Observer {
	public func sendCompleted(with finalValue: Value) {
		sendNext(finalValue)
		sendCompleted()
	}
}

public class AnyMutableProperty<Value>: MutablePropertyProtocol {
	private let _value: () -> Value
	private let _valueSetter: (Value) -> Void
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

	/// Initializes a property as a read-only view of the given property.
	public init<P: MutablePropertyProtocol where P.Value == Value>(_ property: P) {
		_value = { property.value }
		_valueSetter = { property.value = $0 }
		_producer = { property.producer }
		_signal = { property.signal }
	}
}
