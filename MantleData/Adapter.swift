//
//  Adapter.swift
//  MantleData
//
//  Created by Anders on 27/6/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

public protocol Adapter: class {
	associatedtype Target

	func bind(to target: Target)
}

public func <~ <A: Adapter>(left: A.Target, right: A) {
	right.bind(to: left)
}
