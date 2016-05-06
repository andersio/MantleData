//
//  ReactiveSetIndex.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

public struct IndexPath<SectionIndex: ReactiveSetIndex, ObjectIndex: ReactiveSetIndex> {
	let section: SectionIndex
	let row: ObjectIndex
}

/// Index of ReactiveSet

public protocol ReactiveSetIndex: RandomAccessIndexType {
	init<I: ReactiveSetIndex>(converting: I)
	func toIntMax() -> IntMax
}

extension Int: ReactiveSetIndex {
	public init<I: ReactiveSetIndex>(converting index: I) {
		self = Int(index.toIntMax())
	}
}

public struct AnyReactiveSetIndex: ReactiveSetIndex {
	public typealias Distance = IntMax
	public let intMaxValue: Distance

	public init(_ base: Distance) {
		intMaxValue = base
	}

	public func toIntMax() -> IntMax {
		return intMaxValue
	}

	public init<I: ReactiveSetIndex>(converting anotherIndex: I) {
		intMaxValue = anotherIndex.toIntMax()
	}

	public func successor() -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intMaxValue + 1)
	}

	public func predecessor() -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intMaxValue - 1)
	}

	public func advancedBy(n: Distance) -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intMaxValue + n)
	}

	public func distanceTo(end: AnyReactiveSetIndex) -> Distance {
		return end.intMaxValue - intMaxValue
	}
}