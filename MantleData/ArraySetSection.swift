//
//  ArraySetSection.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

final public class ArraySetSection<E: Equatable> {
	private var storage: Array<E>

	private let eventObserver: Observer<ArraySetSectionEvent<Index>, NoError>
	internal let eventSignal: Signal<ArraySetSectionEvent<Index>, NoError>

	internal var disposable: Disposable?

	public var name: ReactiveSetSectionName

	public init(name: ReactiveSetSectionName, values: [E]) {
		self.name = name
		self.storage = values
		(eventSignal, eventObserver) = Signal.pipe()
	}

	public func fetch() throws {
		eventObserver.sendNext(.reloaded)
	}

	internal func pushChanges(_ changes: ArraySetSectionChanges<Index>) {
		eventObserver.sendNext(.updated(changes))
	}

	deinit {
		eventObserver.sendCompleted()
	}
}

extension ArraySetSection: ReactiveSetSection, MutableCollection {
	public typealias Index = Int
	public typealias Iterator = Array<E>.Iterator

	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public func makeIterator() -> IndexingIterator<Array<E>> {
		return storage.makeIterator()
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}

	public subscript(position: Int) -> E {
		get {
			return storage[position]
		}
		set(newValue) {
			storage[position] = newValue
			pushChanges(ArraySetSectionChanges(updatedRows: [position]))
		}
	}

	public subscript(bounds: Range<Int>) -> ArraySlice<E> {
		get {
			return storage[bounds]
		}
		set {
			storage.replaceSubrange(bounds, with: Array(newValue))
		}
	}
}

extension ArraySetSection: RangeReplaceableCollection {
	public convenience init() {
		self.init(name: ReactiveSetSectionName(), values: [])
	}

	public func append(_ newElement: Iterator.Element) {
		replaceSubrange(endIndex ..< endIndex, with: [newElement])
	}

	public func append<S : Sequence where S.Iterator.Element == Iterator.Element>(contentsOf newElements: S) {
		let elements =  Array(newElements)
		if !elements.isEmpty {
			replaceSubrange(endIndex ..< endIndex, with: elements)
		}
	}

	public func insert(_ newElement: Iterator.Element, at i: Index) {
		replaceSubrange(i ..< i, with: [newElement])
	}

	public func insert<C : Collection where C.Iterator.Element == Iterator.Element>(contentsOf newElements: C, at i: Index) {
		let elements = Array(newElements)
		replaceSubrange(i ..< i, with: elements)
	}

	public func removeAll(keepingCapacity keepCapacity: Bool = false) {
		if keepCapacity {
			reserveCapacity(count)
		}
		replaceSubrange(0 ..< endIndex, with: [])
	}

	public func remove(at index: Index) -> Iterator.Element {
		let element = storage[index]
		replaceSubrange(index ..< index + 1, with: [])
		return element
	}

	public func removeFirst() -> Iterator.Element {
		let element = storage[0]
		_ = remove(at: 0)
		return element
	}

	public func removeFirst(_ n: Int) {
		replaceSubrange(0 ..< n, with: [])
	}

	public func removeSubrange(_ subRange: Range<Index>) {
		replaceSubrange(subRange, with: [])
	}

	public func replaceSubrange<C : Collection where C.Iterator.Element == Iterator.Element>(_ subRange: Range<Index>, with newElements: C) {
		storage.replaceSubrange(subRange, with: newElements)

		let newEndIndex = subRange.lowerBound + Int(newElements.count.toIntMax())

		if subRange.count == 0 {
			// Appending at subRange.startIndex, No Replacing & Deletion
			let changes = ArraySetSectionChanges(insertedRows: Array(subRange.lowerBound ..< newEndIndex))
			pushChanges(changes)
		} else {
			let replacingEndIndex = newEndIndex > subRange.upperBound ? subRange.upperBound : newEndIndex
			let updatedRows = Array(subRange.lowerBound ..< replacingEndIndex)

			var insertedRows: [Int]?
			var deletedRows: [Int]?

			if newEndIndex > subRange.upperBound {
				// Appending after replaced items
				insertedRows = Array(subRange.upperBound ..< newEndIndex)
			} else {
				// Deleting after replaced items
				deletedRows = Array(newEndIndex ..< subRange.upperBound)
			}

			let changes = ArraySetSectionChanges(insertedRows: insertedRows,
			                                     deletedRows: deletedRows,
			                                     updatedRows: updatedRows)

			pushChanges(changes)
		}
	}

	public func reserveCapacity(_ n: Array<E>.IndexDistance) {
		storage.reserveCapacity(n)
	}
}

extension ArraySetSection: Equatable {}

public func ==<E>(lhs: ArraySetSection<E>, rhs: ArraySetSection<E>) -> Bool {
	return lhs === rhs
}

internal enum ArraySetSectionEvent<Index: ReactiveSetIndex> {
	case reloaded
	case updated(ArraySetSectionChanges<Index>)
}

internal struct ArraySetSectionChanges<Index: ReactiveSetIndex> {
	var insertedRows: [Index]? = nil
	var deletedRows: [Index]? = nil
	var movedRows: [(from: Index, to: Index)]? = nil
	var updatedRows: [Index]? = nil

	init(insertedRows: [Index]? = nil, deletedRows: [Index]? = nil, movedRows: [(from: Index, to: Index)]? = nil, updatedRows: [Index]? = nil) {
		self.insertedRows = insertedRows
		self.deletedRows = deletedRows
		self.movedRows = movedRows
		self.updatedRows = updatedRows
	}

	func reactiveSetChanges<SectionIndex: ReactiveSetIndex>(for sectionIndex: SectionIndex) -> ReactiveSetChanges {
		var changes = ReactiveSetChanges()
		changes.insertedRows = insertedRows?.map { IndexPath(row: $0.toInt(), section: sectionIndex.toInt()) }
		changes.deletedRows = deletedRows?.map { IndexPath(row: $0.toInt(), section: sectionIndex.toInt()) }
		changes.updatedRows = updatedRows?.map { IndexPath(row: $0.toInt(), section: sectionIndex.toInt()) }
		changes.movedRows = movedRows?.map { (IndexPath(row: $0.from.toInt(), section: sectionIndex.toInt()), IndexPath(row: $0.to.toInt(), section: sectionIndex.toInt())) }
		return changes
	}
}
