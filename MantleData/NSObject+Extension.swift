//
//  NSObject+Bindings.swift
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa

extension NSObject {
	public func bind<Producer: SignalProducerProtocol>(keyPath path: String, from producer: Producer) where Producer.Value: AnyObject, Producer.Error == NoError {
		producer
			.startWithNext { [weak self] value in
				self?.setValue(value, forKeyPath: path)
			}
	}

	public func bind<Producer: SignalProducerProtocol>(keyPath path: String, from producer: Producer) where Producer.Value: CocoaBridgeable, Producer.Error == NoError {
		producer
			.startWithNext { [weak self] value in
				self?.setValue(value.cocoaValue, forKeyPath: path)
		}
	}

	public func bind<Producer: SignalProducerProtocol>(keyPath path: String, onMainQueueFrom producer: Producer) where Producer.Value: AnyObject, Producer.Error == NoError {
		bind(keyPath: path, from: producer.observe(on: UIScheduler()))
	}

	public func bind<Producer: SignalProducerProtocol>(keyPath path: String, onMainQueueFrom producer: Producer) where Producer.Value: CocoaBridgeable, Producer.Error == NoError {
		bind(keyPath: path, from: producer.observe(on: UIScheduler()))
	}

	public var willDeinitProducer: SignalProducer<(), NoError> {
		return rac_willDeallocSignal()
			.toSignalProducer()
			.map { _ in }
			.flatMapError { _ in .empty }
	}
}
