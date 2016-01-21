//
//  RAC+Extensions.swift
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa

final public class Queue {
	public static let mainQueue = Queue()

	private(set) public var underlyingQueue: dispatch_queue_t
	public let isMainQueue: Bool

	public init(concurrency: Concurrency, name: String = "") {
		underlyingQueue = dispatch_queue_create(name, concurrency.libdispatchValue)
		dispatch_queue_set_specific(underlyingQueue, &underlyingQueue, &underlyingQueue, nil)
		isMainQueue = false
	}

	internal init() {
		underlyingQueue = dispatch_get_main_queue()
		isMainQueue = true
	}

	public func acquire(@noescape action: () -> Void) {
		if isMainQueue {
			if NSThread.isMainThread() {
				action()
				return
			}
		} else {
			if nil != dispatch_get_specific(&underlyingQueue) {
				action()
				return
			}
		}

		_mantleData_dispatch_sync(underlyingQueue, action)
	}

	public func acquiringFenceWith(@noescape action: () -> Void) {
		_mantleData_dispatch_barrier_sync(underlyingQueue, action)
	}

	public func append(action: () -> Void) {
		dispatch_async(underlyingQueue, action)
	}

	public func appendFenceWith(action: () -> Void) {
		dispatch_barrier_async(underlyingQueue, action)
	}

	public func appendAfter(time: Double, action: () -> Void) {
		let time = dispatch_time(DISPATCH_TIME_NOW, Int64(time * Double(NSEC_PER_SEC)))
		dispatch_after(time, underlyingQueue, action)
	}

	public func suspend() {
		dispatch_suspend(underlyingQueue)
	}

	public func resume() {
		dispatch_resume(underlyingQueue)
	}

	public enum Concurrency {
		case Concurrent
		case Serial

		var libdispatchValue: dispatch_queue_attr_t {
			switch self {
			case .Concurrent: return DISPATCH_QUEUE_CONCURRENT
			case .Serial: return DISPATCH_QUEUE_SERIAL
			}
		}
	}
}