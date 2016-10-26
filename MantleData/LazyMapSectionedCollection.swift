//
//  ViewModelMapper.swift
//  MantleData
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

public final class LazyMapSectionedCollection<U>: SectionedCollection {
	public typealias Index = IndexPath

	private let set: _AnySectionedCollectionBox<U>

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

	public func index(after i: Index) -> Index {
		return set.index(after: i)
	}

	public func index(before i: Index) -> Index {
		return set.index(before: i)
	}

	public func sectionName(for section: Int) -> String? {
		return set.sectionName(for: section)
	}

	public func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}

	public subscript(row row: Int, section section: Int) -> U {
		return set[row: row, section: section]
	}

	public init<R: SectionedCollection>(_ set: R, transform: @escaping (R.Iterator.Element) -> U) {
		self.set = _LazyMapSectionedCollectionBase(set, transform: transform)
	}
}
