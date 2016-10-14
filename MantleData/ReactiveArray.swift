//
//  ArraySet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveSwift
import enum Result.NoError

// Root
final public class ReactiveArray<E> {
	public var name: String? = nil

	public let events: Signal<SectionedCollectionEvent, NoError>
	fileprivate let eventObserver: Observer<SectionedCollectionEvent, NoError>

	fileprivate var storage: [E] = []

	public init<S: Sequence>(_ content: S) where S.Iterator.Element == E {
		(events, eventObserver) = Signal.pipe()
		storage = Array(content)
	}

	public required convenience init() {
		self.init([])
	}

	deinit {
		replaceSubrange(startIndex ..< endIndex, with: [])
		eventObserver.sendCompleted()
	}
}

extension ReactiveArray: SectionedCollection {
	public typealias Index = IndexPath

	public var sectionCount: Int {
		return 0
	}

	public var startIndex: IndexPath {
		return IndexPath(row: storage.startIndex, section: 0)
	}

	public var endIndex: IndexPath {
		return IndexPath(row: storage.endIndex, section: 0)
	}

	public func index(after i: IndexPath) -> IndexPath {
		return IndexPath(row: i.row + 1, section: 0)
	}

	public func index(before i: IndexPath) -> IndexPath {
		return IndexPath(row: i.row - 1, section: 0)
	}

	public subscript(row row: Int, section section: Int) -> E {
		get { return storage[row] }
	}

	public subscript(index: IndexPath) -> E {
		get { return storage[index.row] }
		set(newValue) { storage[index.row] = newValue }
	}

	public subscript(subRange: Range<IndexPath>) -> MutableRandomAccessSlice<ReactiveArray<E>> {
		get { return MutableRandomAccessSlice(base: self, bounds: subRange) }
		set { replaceSubrange(subRange, with: newValue) }
	}

	public func sectionName(for section: Int) -> String? {
		return nil
	}

	public func rowCount(for section: Int) -> Int {
		return section > 0 ? 0 : storage.count
	}
}

extension ReactiveArray: MutableCollection { }

extension ReactiveArray: RangeReplaceableCollection {
	public func replaceSubrange<C>(_ subRange: Range<IndexPath>, with newElements: C) where C : Collection, C.Iterator.Element == E {
		let subRange = subRange.lowerBound.row ..< subRange.upperBound.row
		storage.replaceSubrange(subRange, with: newElements)

		let newElementsCount = Int(newElements.count.toIntMax())
		let removedCount = Swift.min(newElementsCount, subRange.count)
		let insertedCount = Swift.max(0, newElementsCount - removedCount)

		let removed = subRange.lowerBound ..< subRange.lowerBound + removedCount
		let inserted = removed.upperBound ..< removed.upperBound + insertedCount

		let changes = SectionedCollectionChanges(
			deletedRows: removed.map { IndexPath(row: $0, section: 0) },
			insertedRows: inserted.map { IndexPath(row: $0, section: 0) },
			movedRows: [],
			deletedSections: [],
			insertedSections: []
		)

		eventObserver.send(value: .updated(changes))
	}
}

