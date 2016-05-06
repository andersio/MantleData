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