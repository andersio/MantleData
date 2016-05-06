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
final public class ArraySet<E: Equatable> {
	public let eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError>
	private let eventObserver: Observer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError>

	private var storage: [ArraySetSection<E>] = []

	public required convenience init() {
		self.init(sectionCount: 0)
	}

	public init(sectionCount: Int) {
		(eventProducer, eventObserver) = SignalProducer.buffer(0)

		appendContentsOf((0 ..< sectionCount)
			.map { _ in ArraySetSection(name: ReactiveSetSectionName(),
				values: []) })
	}

	internal func pushChanges(changes: ArraySetSectionChanges<Generator.Element.Index>, from section: ArraySetSection<E>? = nil) {
		if let section = section {
			let sectionIndex = storage.indexOf(section)!
			eventObserver.sendNext(.updated(changes.reactiveSetChanges(for: sectionIndex)))
		}
	}

	internal func pushChanges(changes: ReactiveSetChanges<ArraySet.Index, ArraySet.Generator.Element.Index>) {
		eventObserver.sendNext(.updated(changes))
	}

	deinit {
		replaceRange(0 ..< storage.count, with: [])
		eventObserver.sendCompleted()
	}
}

extension ArraySet: ReactiveSet {
	public typealias Index = Int
	public typealias Generator = AnyReactiveSetIterator<ArraySetSection<E>>

	public func fetch() throws {
		eventObserver.sendNext(.reloaded)
	}

	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public func generate() -> Generator {
		var generator = storage.generate()
		return AnyReactiveSetIterator {
			return generator.next()
		}
	}

	public subscript(position: Int) -> ArraySetSection<E> {
		get {
			return storage[position]
		}
		set(newValue) {
			replaceRange(position ..< position + 1, with: [newValue])
		}
	}

	public subscript(bounds: Range<Int>) -> ArraySlice<ArraySetSection<E>> {
		get {
			return storage[bounds]
		}
		set {
			replaceRange(bounds, with: newValue)
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
}

extension ArraySet: MutableCollectionType { }

extension ArraySet: RangeReplaceableCollectionType {
	public func append(newElement: Generator.Element) {
		replaceRange(endIndex ..< endIndex, with: [newElement])
	}

	public func appendContentsOf<S : SequenceType where S.Generator.Element == Generator.Element>(newElements: S) {
		let elements =  Array(newElements)
		replaceRange(endIndex ..< endIndex, with: elements)
	}

	public func insert(newElement: Generator.Element, atIndex i: Index) {
		replaceRange(i ..< i, with: [newElement])
	}

	public func insertContentsOf<C : CollectionType where C.Generator.Element == Generator.Element>(newElements: C, at i: Index) {
		let elements = Array(newElements)
		replaceRange(i ..< i, with: elements)
	}

	public func removeAll(keepCapacity keepCapacity: Bool = false) {
		if keepCapacity {
			reserveCapacity(count)
		}
		replaceRange(0 ..< endIndex, with: [])
	}

	public func removeAtIndex(index: Index) -> Generator.Element {
		let element = storage[index]
		replaceRange(index ..< index + 1, with: [])
		return element
	}

	public func removeFirst() -> Generator.Element {
		let element = storage[0]
		removeAtIndex(0)
		return element
	}

	public func removeFirst(n: Int) {
		replaceRange(0 ..< n, with: [])
	}

	public func removeRange(subRange: Range<Index>) {
		replaceRange(subRange, with: [])
	}

	public func replaceRange<C : CollectionType where C.Generator.Element == Generator.Element>(subRange: Range<Index>, with newElements: C) {
		func dispose(range: Range<Index>) {
			for position in range {
				if let disposable = storage[position].disposable where !disposable.disposed {
					disposable.dispose()
					storage[position].disposable = nil
				}
			}
		}

		func register(sections: ArraySlice<Generator.Element>, from startIndex: Index) {
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
		let newEndIndex = subRange.startIndex + Int(newElements.count.toIntMax())

		var insertedSections = [Int]()
		var deletedSections = [Int]()

		let replacingEndIndex = min(newEndIndex, subRange.endIndex)
		let replacedSections = subRange.startIndex ..< replacingEndIndex

		dispose(replacedSections)
		deletedSections.appendContentsOf(Array(replacedSections))

		let newElementsRange = newElements.startIndex ..< newElements.startIndex.advancedBy(replacedSections.count)
		register(newElements[newElementsRange], from: replacedSections.startIndex)
		insertedSections.appendContentsOf(Array(newElementsRange))

		let changes: ReactiveSetChanges<ArraySet.Index, ArraySet.Generator.Element.Index>

		if newEndIndex > subRange.endIndex {
			// Appending after replaced items
			let rangeForAppendedItems = subRange.endIndex ..< newEndIndex
			insertedSections.appendContentsOf(Array(rangeForAppendedItems))

			changes = ReactiveSetChanges(deletedSections: deletedSections,
			                             insertedSections: insertedSections)

			let newElementsRange = newElementsRange.endIndex ..< newElements.endIndex
			register(newElements[newElementsRange], from: rangeForAppendedItems.startIndex)
		} else {
			// Deleting after replaced items
			let removingRange = newEndIndex ..< subRange.endIndex

			deletedSections.appendContentsOf(Array(removingRange))
			changes = ReactiveSetChanges(deletedSections: deletedSections,
			                             insertedSections: insertedSections)

			dispose(removingRange)
		}

		storage.replaceRange(subRange, with: newElements)
		pushChanges(changes)
	}

	public func reserveCapacity(n: Index.Distance) {
		storage.reserveCapacity(n)
	}
}