//
//  ReactiveSetIndex.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

/// Index of ReactiveSet

public protocol ReactiveSetIndicesIterator: IteratorProtocol {
	associatedtype Element: ReactiveSetIndex
}

public protocol ReactiveSetIndices: BidirectionalCollection {
	associatedtype Iterator: ReactiveSetIndicesIterator
}

public protocol ReactiveSetIndex: Strideable {
	associatedtype Stride: SignedInteger

	init<I: ReactiveSetIndex>(converting: I)
	func toInt() -> Int
}

extension Int: ReactiveSetIndex {
	public init<I: ReactiveSetIndex>(converting index: I) {
		self = Int(index.toInt())
	}

	public func toInt() -> Int {
		return self
	}
}
