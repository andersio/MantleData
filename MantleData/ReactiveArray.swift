//
//  ArraySet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

// Root
final public class ReactiveArray<E> {
	public var name: String? = nil

	public let events: Signal<SectionedCollectionEvent, NoError>
	private let eventObserver: Observer<SectionedCollectionEvent, NoError>

	private var storage: [E] = []

	public init<S: Sequence where S.Iterator.Element == E>(_ content: S) {
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

	public subscript(position: IndexPath) -> E {
		get {
			return storage[position.row]
		}
		set(newValue) {
			storage[position.row] = newValue
		}
	}

	public subscript(subRange: Range<IndexPath>) -> MutableRandomAccessSlice<ReactiveArray<E>> {
		get { return MutableRandomAccessSlice(base: self, bounds: subRange) }
		set { replaceSubrange(subRange, with: newValue) }
	}

	public func fetch(trackingChanges startTracking: Bool) throws {
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
	public func replaceSubrange<C where C : Collection, C.Iterator.Element == E>(_ subRange: Range<IndexPath>, with newElements: C) {
		let subRange = subRange.lowerBound.row ..< subRange.upperBound.row
		storage.replaceSubrange(subRange, with: newElements)

		let newElementsCount = Int(newElements.count.toIntMax())
		let removedCount = Swift.min(newElementsCount, subRange.count)
		let insertedCount = Swift.max(0, newElementsCount - removedCount)

		let removed = subRange.lowerBound ..< subRange.lowerBound + removedCount
		let inserted = removed.upperBound ..< removed.upperBound + insertedCount

		let changes = SectionedCollectionChanges(
			deletedRows: !removed.isEmpty ? removed.map { IndexPath(row: $0, section: 0) } : nil,
			insertedRows: !inserted.isEmpty ? inserted.map { IndexPath(row: $0, section: 0) } : nil,
			movedRows: nil,
			deletedSections: nil,
			insertedSections: nil
		)

		eventObserver.sendNext(.updated(changes))
	}
}
