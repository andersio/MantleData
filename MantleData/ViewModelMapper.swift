//
//  ViewModelMapper.swift
//  MantleData
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

/// `ViewModelMapper` is a type-erased view to `SectionedCollection`. For every
/// object, it returns an action that can be applied on any instance of
/// `ViewModel`, which triggers the associated configurator of the mapper.
public final class ViewModelMapper<ViewModel>: SectionedCollection {
	public typealias Index = IndexPath

	public var sectionNameTransform: ((String?) -> String?)? = nil

  private let set: _AnySectionedCollectionBox<(ViewModel) -> Void>

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
		let name = set.sectionName(for: section)
		return sectionNameTransform?(name) ?? name
	}

	public func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}

	public subscript(row row: Int, section section: Int) -> (ViewModel) -> Void {
		return set[row: row, section: section]
	}

	public init<R: SectionedCollection>(_ set: R, binder: @escaping (R.Iterator.Element, ViewModel) -> Void) {
		self.set = _ViewModelCollectionBoxBase(set, binder: binder)
	}
}
