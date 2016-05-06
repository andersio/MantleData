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