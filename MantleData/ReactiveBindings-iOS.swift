//
//  ReactiveBindings.swift
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa

extension UITableView {
	public func bind<V: ViewModel>(set: ViewModelSet<V>, configuration: TableViewAdapterConfiguration<V>) {
		let adapter = TableViewAdapter(set: set, configuration: configuration)
		adapter.bind(self)

		_setAssociatedObject(adapter, key: "tableViewAdapter")
	}
}

extension NSObject {
	public func bind<Producer: SignalProducerType where Producer.Value: AnyObject>(keyPath: String, from producer: Producer) {
		producer
			.startWithNext { [weak self] value in
				self?.setValue(value, forKeyPath: keyPath)
			}
	}

	public func bind<Producer: SignalProducerType where Producer.Value: CocoaBridgeable>(keyPath: String, from producer: Producer) {
		producer
			.startWithNext { [weak self] value in
				self?.setValue(value.cocoaValue, forKeyPath: keyPath)
		}
	}

	public func bind<Producer: SignalProducerType where Producer.Value: AnyObject>(keyPath: String, onMainQueueFrom producer: Producer) {
		bind(keyPath, from: producer.observeOn(UIScheduler()))
	}

	public func bind<Producer: SignalProducerType where Producer.Value: CocoaBridgeable>(keyPath: String, onMainQueueFrom producer: Producer) {
		bind(keyPath, from: producer.observeOn(UIScheduler()))
	}
}