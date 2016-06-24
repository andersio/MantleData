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
final public class ArraySet<E: Equatable>: ReactiveSet {
	public typealias Index = Int
	public typealias IndexDistance = Int
	public typealias Iterator = DefaultReactiveSetIterator<ArraySetSection<E>>

	public let eventProducer: SignalProducer<ReactiveSetEvent, NoError>
	private let eventObserver: Observer<ReactiveSetEvent, NoError>

	private var storage: [ArraySetSection<E>] = []

	public required convenience init() {
		self.init(sectionCount: 0)
	}

	public init(sectionCount: Int) {
		(eventProducer, eventObserver) = SignalProducer.buffer(0)

		self.append(contentsOf: (0 ..< sectionCount)
			.map { _ in ArraySetSection(name: ReactiveSetSectionName(),
				values: []) })
	}

	public func fetch(startTracking: Bool) throws {
		eventObserver.sendNext(.reloaded)
	}

	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public func makeIterator() -> Iterator {
		return DefaultReactiveSetIterator(for: self)
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}

	public subscript(position: Int) -> ArraySetSection<E> {
		get {
			return storage[position]
		}
		set(newValue) {
			replaceSubrange(position ..< position + 1, with: [newValue])
		}
	}

	public subscript(bounds: Range<Int>) -> ArraySlice<ArraySetSection<E>> {
		get {
			return storage[bounds]
		}
		set {
			replaceSubrange(bounds, with: newValue)
		}
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		for index in storage.indices {
			if storage[index].contains(object) {
				return storage[index].name
			}
		}

		return nil
	}

	public func indexPath(of element: Iterator.Element.Iterator.Element) -> IndexPath? {
		for (sectionIndex, section) in self.enumerated() {
			for (rowIndex, row) in section.enumerated() {
				if row == element {
					return IndexPath(row: rowIndex, section: sectionIndex)
				}
			}
		}

		return nil
	}

	internal func pushChanges(_ changes: ArraySetSectionChanges<Iterator.Element.Index>, from section: ArraySetSection<E>? = nil) {
		if let section = section {
			let sectionIndex = storage.index(of: section)!
			eventObserver.sendNext(.updated(changes.reactiveSetChanges(for: sectionIndex)))
		}
	}

	internal func pushChanges(_ changes: ReactiveSetChanges) {
		eventObserver.sendNext(.updated(changes))
	}

	deinit {
		replaceSubrange(0 ..< storage.count, with: [])
		eventObserver.sendCompleted()
	}
}

extension ArraySet: MutableCollection { }

extension ArraySet: RangeReplaceableCollection {
	public func append(_ newElement: Iterator.Element) {
		replaceSubrange(endIndex ..< endIndex, with: [newElement])
	}

	public func append<S : Sequence where S.Iterator.Element == Iterator.Element>(contentsOf newElements: S) {
		let elements =  Array(newElements)
		replaceSubrange(endIndex ..< endIndex, with: elements)
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
		func dispose(_ range: CountableRange<Index>) {
			for position in range {
				if let disposable = storage[position].disposable where !disposable.disposed {
					disposable.dispose()
					storage[position].disposable = nil
				}
			}
		}

		func register(_ sections: ArraySlice<Iterator.Element>, from startIndex: Index) {
			for section in sections {
				let disposable = section.eventProducer
					.startWithNext { [unowned self] event in
						switch event {
						case .reloaded:
							break

						case let .updated(changes):
							self.pushChanges(changes, from: section)
						}
				}

				section.disposable = disposable
			}
		}

		let newElements = Array(newElements)
		let newEndIndex = subRange.lowerBound + newElements.count

		var insertedSections = [Int]()
		var deletedSections = [Int]()

		let replacingEndIndex = subRange.upperBound > newEndIndex ? newEndIndex : subRange.upperBound
		let replacedSections = subRange.lowerBound ..< replacingEndIndex

		dispose(replacedSections)
		deletedSections.append(contentsOf: Array(replacedSections))

		let newElementsRange = newElements.startIndex ..< newElements.startIndex.advanced(by: replacedSections.count)
		register(newElements[newElementsRange], from: replacedSections.startIndex)
		insertedSections.append(contentsOf: Array(newElementsRange))

		let changes: ReactiveSetChanges

		if newEndIndex > subRange.upperBound {
			// Appending after replaced items
			let rangeForAppendedItems = subRange.upperBound ..< newEndIndex
			insertedSections.append(contentsOf: Array(rangeForAppendedItems))

			changes = ReactiveSetChanges(deletedSections: deletedSections,
			                             insertedSections: insertedSections)

			let newElementsRange = newElementsRange.endIndex ..< newElements.endIndex
			register(newElements[newElementsRange], from: rangeForAppendedItems.startIndex)
		} else {
			// Deleting after replaced items
			let removingRange = newEndIndex ..< subRange.upperBound

			deletedSections.append(contentsOf: Array(removingRange))
			changes = ReactiveSetChanges(deletedSections: deletedSections,
			                             insertedSections: insertedSections)

			dispose(removingRange)
		}

		storage.replaceSubrange(subRange, with: newElements)
		pushChanges(changes)
	}

	public func reserveCapacity(_ n: IndexDistance) {
		storage.reserveCapacity(n)
	}
}
