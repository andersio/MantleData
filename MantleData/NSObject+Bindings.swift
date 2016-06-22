//
//  NSObject+Bindings.swift
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa

extension NSObject {
	public func bind<Producer: SignalProducerType where Producer.Value: AnyObject>(keyPath path: String, from producer: Producer) {
		producer
			.startWithNext { [weak self] value in
				self?.setValue(value, forKeyPath: path)
			}
	}

	public func bind<Producer: SignalProducerType where Producer.Value: CocoaBridgeable>(keyPath path: String, from producer: Producer) {
		producer
			.startWithNext { [weak self] value in
				self?.setValue(value.cocoaValue, forKeyPath: path)
		}
	}

	public func bind<Producer: SignalProducerType where Producer.Value: AnyObject>(keyPath path: String, onMainQueueFrom producer: Producer) {
		bind(keyPath: path, from: producer.observeOn(UIScheduler()))
	}

	public func bind<Producer: SignalProducerType where Producer.Value: CocoaBridgeable>(keyPath path: String, onMainQueueFrom producer: Producer) {
		bind(keyPath: path, from: producer.observeOn(UIScheduler()))
	}
}