//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

public protocol SectionedCollection: class, _SectionedCollectionIndexable, RandomAccessCollection {
	associatedtype Index: SectionedCollectionIndex

	var events: Signal<SectionedCollectionEvent, NoError> { get }
	var sectionCount: Int { get }

	func sectionName(for section: Int) -> String?
	func rowCount(for section: Int) -> Int

	subscript(row row: Int, section section: Int) -> Iterator.Element { get }
}

// `SectionedCollection` provides a default implementation for `subscript.get`
// that accepts `Index`, which requires a bunch of workarounds to the limits of 
// associated type inference.

public protocol _SectionedCollectionIndexable: _SectionedCollectionIndexableBase {
	associatedtype SubSequence = SectionedSlice<Self>
	associatedtype Index: SectionedCollectionIndex

	func index(before i: Index) -> Index
	func index(after i: Index) -> Index
	func distance(from start: Index, to end: Index) -> Int
	func index(_ i: Index, offsetBy n: Int) -> Index

	subscript(index: Index) -> _Element { get }
	subscript(row row: Int, section section: Int) -> _Element { get }
	subscript(range: Range<Index>) -> SubSequence { get }
}

public protocol _SectionedCollectionIndexableBase {
	associatedtype _Element
	associatedtype Index: SectionedCollectionIndex

	subscript(index: Index) -> _Element { get }
	subscript(row row: Int, section section: Int) -> _Element { get }
}

extension _SectionedCollectionIndexableBase {
	public subscript(index: Index) -> _Element {
		return self[row: index.row, section: index.section]
	}
}

extension _SectionedCollectionIndexable where SubSequence == SectionedSlice<Self> {
	public subscript(range: Range<Index>) -> SectionedSlice<Self> {
		return SectionedSlice(base: self, bounds: range)
	}
}

public struct SectionedSlice<S: _SectionedCollectionIndexable>: _SectionedCollectionIndexable, RandomAccessCollection {
	public let base: S
	public let bounds: Range<S.Index>

	public init(base: S, bounds: Range<S.Index>) {
		self.base = base
		self.bounds = bounds
	}

	public var startIndex: S.Index {
		return bounds.lowerBound
	}

	public var endIndex: S.Index {
		return bounds.upperBound
	}

	public func index(before i: S.Index) -> S.Index {
		return base.index(before: i)
	}

	public func index(after i: S.Index) -> S.Index {
		return base.index(before: i)
	}

	public func index(_ i: S.Index, offsetBy n: Int) -> S.Index {
		return base.index(i, offsetBy: n)
	}

	public subscript(row row: Int, section section: Int) -> S._Element {
		return base[row: row, section: section]
	}
}

public protocol SectionedCollectionIndex: Comparable {
	var section: Int { get }
	var row: Int { get }

	init<I: SectionedCollectionIndex>(_ index: I)
	init(row: Int, section: Int)
}

extension IndexPath: SectionedCollectionIndex {
	public init<I: SectionedCollectionIndex>(_ index: I) {
		self.init(row: index.row, section: index.section)
	}
}
