//
//  ViewModelSet.swift
//  MantleData
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import ReactiveCocoa

/// `ViewModelSet` is a type-erased collection view to a `ReactiveSet` implementation, which
/// maps view models of type `U` from the underlying set of `U.MappingObject` objects.
public final class ViewModelMappingSet<U: ViewModel>: SectionedCollection {
	public typealias Index = IndexPath

	public var sectionNameTransform: ((String?) -> String?)? = nil

  private let set: _AnySectionedCollectionBox<U.MappingObject>
	internal let factory: (U.MappingObject) -> U

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

	public func fetch(trackingChanges shouldTrackChanges: Bool = true) throws {
		try set.fetch(trackingChanges: shouldTrackChanges)
	}

	public func sectionName(for section: Int) -> String? {
		let name = set.sectionName(for: section)
		return sectionNameTransform?(name) ?? name
	}

	public func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}

	public subscript(position: IndexPath) -> U {
		return factory(set[position])
	}

	public subscript(subRange: Range<IndexPath>) -> RandomAccessSlice<ViewModelMappingSet<U>> {
		return RandomAccessSlice(base: self, bounds: subRange)
	}
	
	public init<R: SectionedCollection where R.Iterator.Element == U.MappingObject>(_ set: R, factory: (U.MappingObject) -> U) {
    self.set = _AnySectionedCollectionBoxBase(set)
		self.factory = factory
	}
}
