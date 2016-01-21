//
//  Attribute.swift
//  MantleData
//
//  Created by Anders on 13/9/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa
/*
final public class Attribute<Value: CocoaBridgeable where Value.Inner: CocoaBridgeable> {
	private unowned var object: Object
	private let keyPath: String

  public var value: Value {
    get {
			return Value(cocoaValue: object.valueForKeyPath(keyPath))
		}
    set {
			object.setValue(newValue.cocoaValue, forKey: keyPath)
		}
  }

  private(set) public lazy var producer: SignalProducer<Value, NoError> = { [unowned self] in
		return self.object.producerFor(self.keyPath, type: Value.self)
  }()

	private(set) public lazy var signal: Signal<Value, NoError> = { [unowned self] in
		var returnSignal: Signal<Value, NoError>?
		self.producer.startWithSignal { signal, _ in
			returnSignal = signal
		}
		return returnSignal!
  }()

  private init(keyPath: String, object: Object) {
    self.object = object
    self.keyPath = keyPath
  }
}

extension Attribute: MutablePropertyType { }

extension Object {
	final public func attributeFor<Value: CocoaBridgeable where Value.Inner: CocoaBridgeable>(keyPath: String) -> Attribute<Value> {
    let property = Attribute<Value>(keyPath: keyPath, object: self)
    return property
  }
}*/