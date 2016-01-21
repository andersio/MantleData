//
//  Base.swift
//  MantleData
//
//  Created by Anders on 13/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import ReactiveCocoa

public class Base {
  final private var willDeinitObserver: Signal<(), NoError>.Observer! = nil
  final private(set) public lazy var willDeinitProducer: SignalProducer<(), NoError> = { [unowned self] in
    let (p, o) = SignalProducer<(), NoError>.buffer(0)
    self.willDeinitObserver = o
    return p
  }()

	public init() {}
  
  deinit {
    willDeinitObserver?.sendCompleted()
  }
}

extension NSObject {
  final public var willDeinitProducer: SignalProducer<(), NoError> {
    return rac_willDeallocSignal()
      .toSignalProducer()
      .map { _ in }
      .flatMapError { _ in .empty }
  }

	final public func setObject(object: AnyObject, key: UnsafePointer<Void>, weak: Bool = false) {
		objc_setAssociatedObject(self, key, object, weak ? .OBJC_ASSOCIATION_ASSIGN : .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
	}

	final public func objectFor<U: AnyObject>(key: UnsafePointer<Void>) -> U? {
		return objc_getAssociatedObject(self, key) as? U
	}
}