//
//  Dispatch.swift
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa

public typealias Queue = dispatch_queue_t
public var mainQueue = dispatch_get_main_queue()

extension dispatch_queue_t {
	public func perform<Result>(@noescape action: () -> Result) -> Result {
		var result: Result!
		_mantleData_dispatch_sync(self) {
			result = action()
		}
		return result
	}

	public func performWithBarrier<Result>(@noescape blockingAction: () -> Result) -> Result {
		var result: Result!
		_mantleData_dispatch_barrier_sync(self) {
			result = blockingAction()
		}
		return result
	}

	public func schedule(action: () -> Void) {
		dispatch_async(self, action)
	}

	public func scheduleWithBarrier(blockingAction: () -> Void) {
		dispatch_barrier_async(self, blockingAction)
	}

	public func schedule(after second: NSTimeInterval, action: () -> Void) {
		let time = dispatch_time(DISPATCH_TIME_NOW, Int64(second * Double(NSEC_PER_SEC)))
		dispatch_after(time, self, action)
	}

	public func suspend() {
		dispatch_suspend(self)
	}

	public func resume() {
		dispatch_resume(self)
	}
}