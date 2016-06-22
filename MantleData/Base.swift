//
//  Base.swift
//  MantleData
//
//  Created by Anders on 13/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa
import enum Result.NoError
public typealias NoError = Result.NoError

public class Base {
  final private let willDeinitObserver = Atomic<(Signal<(), NoError>, Signal<(), NoError>.Observer)?>(nil)
  final public var willDeinitProducer: SignalProducer<(), NoError> {
		return SignalProducer { [weak willDeinitObserver] observer, disposable in
			guard let willDeinitObserver = willDeinitObserver else {
				observer.sendInterrupted()
				return
			}

			var deinitSignal: Signal<(), NoError>!

			willDeinitObserver.modify { oldValue in
				if let tuple = oldValue {
					deinitSignal = tuple.0
					return tuple
				} else {
					let (signal, observer) = Signal<(), NoError>.pipe()
					deinitSignal = signal
					return (signal, observer)
				}
			}

			disposable += deinitSignal.observe(observer)
		}
  }

	public init() {}

  deinit {
		willDeinitObserver.withValue { tuple in
			tuple?.1.sendCompleted()
		}
  }
}
