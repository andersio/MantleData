//
//  ExistentialCollections.swift
//  MantleData
//
//  Created by Anders on 24/6/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

/// `AnyReactiveSet` assumes the wrapping ReactiveSet always uniformly index
/// its elements with 1 unit of distance in integer.
public final class AnySectionedCollection<E>: SectionedCollection {
	public typealias Index = IndexPath

	private let set: _AnySectionedCollectionBox<E>

	public var events: Signal<SectionedCollectionEvent, NoError> {
		return set.events
	}

	public var sectionCount: Int {
		return set.sectionCount
	}

	public var startIndex: IndexPath {
		return set.startIndex
	}

	public var endIndex: IndexPath {
		return set.endIndex
	}

	public func index(after i: IndexPath) -> IndexPath {
		return set.index(after: i)
	}

	public func index(before i: IndexPath) -> IndexPath {
		return set.index(before: i)
	}

	public init<R: SectionedCollection>(_ set: R) where R.Iterator.Element == E {
		self.set = _AnySectionedCollectionBoxBase(set)
	}

	public func fetch(trackingChanges shouldTrackChanges: Bool) throws {
		try set.fetch(trackingChanges: shouldTrackChanges)
	}

	public func sectionName(for section: Int) -> String? {
		return set.sectionName(for: section)
	}

	public func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}

	public subscript(position: IndexPath) -> E {
		return set[position]
	}

	public subscript(subRange: Range<IndexPath>) -> RandomAccessSlice<AnySectionedCollection<E>> {
		return RandomAccessSlice(base: self, bounds: subRange)
	}
}
