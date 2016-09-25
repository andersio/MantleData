//
//  ViewModelSet.swift
//  MantleData
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import ReactiveSwift

/// `ViewModelSet` is a type-erased collection view to a `ReactiveSet` implementation, which
/// maps view models of type `U` from the underlying set of `U.MappingObject` objects.
public final class FlattenSectionedCollection<S: SectionedCollection>: ReactiveCollection {
	public let base: S
	public let focus: Int

	public var events: Signal<ReactiveCollectionEvent, NoError> {
		return base.events.map { [focus = self.focus] in
			return ReactiveCollectionEvent(clamping: $0, forSection: focus)
		}
	}

	public var startIndex: Int {
		return 0
	}

	public var endIndex: Int {
		return base.rowCount(for: focus)
	}

	public func index(after i: Int) -> Int {
		return i + 1
	}

	public func index(before i: Int) -> Int {
		return i - 1
	}

	public func fetch(trackingChanges shouldTrackChanges: Bool = true) throws {
		try base.fetch(trackingChanges: shouldTrackChanges)
	}

	public subscript(position: Int) -> S.Iterator.Element {
		return base[section: focus, row: position]
	}

	public init(_ base: S, focusing section: Int) {
		self.base = base
		self.focus = section
	}
}
