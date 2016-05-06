//
//  ReactiveSetIndex.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

public struct ReactiveSetIndexPath<SectionIndex: ReactiveSetIndex, RowIndex: ReactiveSetIndex>: Comparable {
	public let section: SectionIndex
	public let row: RowIndex

	public func typeErased() -> ReactiveSetIndexPath<AnyReactiveSetIndex, AnyReactiveSetIndex> {
		return ReactiveSetIndexPath<AnyReactiveSetIndex, AnyReactiveSetIndex>(section: AnyReactiveSetIndex(converting: section),
		                                                           row: AnyReactiveSetIndex(converting: row))
	}
}

public func == <SectionIndex: ReactiveSetIndex, RowIndex: ReactiveSetIndex>
	(left: ReactiveSetIndexPath<SectionIndex, RowIndex>, right: ReactiveSetIndexPath<SectionIndex, RowIndex>) -> Bool {
	return left.section == right.section && left.row == right.row
}

public func >= <SectionIndex: ReactiveSetIndex, RowIndex: ReactiveSetIndex>
	(left: ReactiveSetIndexPath<SectionIndex, RowIndex>, right: ReactiveSetIndexPath<SectionIndex, RowIndex>) -> Bool {
	return left.section > right.section || (left.section == right.section && left.row >= right.row)
}

public func < <SectionIndex: ReactiveSetIndex, RowIndex: ReactiveSetIndex>
	(left: ReactiveSetIndexPath<SectionIndex, RowIndex>, right: ReactiveSetIndexPath<SectionIndex, RowIndex>) -> Bool {
	return left.section < right.section || (left.section == right.section && left.row < right.row)
}

/// Index of ReactiveSet

public protocol ReactiveSetIndex: RandomAccessIndexType {
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

public struct AnyReactiveSetIndex: ReactiveSetIndex {
	public typealias Distance = Int
	public let intValue: Distance

	public init(_ base: Distance) {
		intValue = base
	}

	public func toInt() -> Int {
		return intValue
	}

	public init<I: ReactiveSetIndex>(converting anotherIndex: I) {
		intValue = anotherIndex.toInt()
	}

	public func successor() -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intValue + 1)
	}

	public func predecessor() -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intValue - 1)
	}

	public func advancedBy(n: Distance) -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intValue + n)
	}

	public func distanceTo(end: AnyReactiveSetIndex) -> Distance {
		return end.intValue - intValue
	}
}