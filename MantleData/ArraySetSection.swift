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

	private let eventObserver: Observer<ReactiveSetEvent, NoError>
	public let eventProducer: SignalProducer<ReactiveSetEvent, NoError>
	private var bufferingChanges: [ReactiveSetEvent.Changes]?

	internal var disposable: Disposable?

	public var name: ReactiveSetSectionName

	public init(name: ReactiveSetSectionName, values: [E]) {
		self.name = name
		self.storage = values
		(eventProducer, eventObserver) = SignalProducer.buffer(0)
	}

	public func fetch() throws {
		eventObserver.sendNext(.Reloaded)
	}

	public func modify(@noescape action: () throws -> Void) rethrows {
		bufferingChanges = []
		try action()

		if !bufferingChanges!.isEmpty {
			let changes = ReactiveSetEvent.Changes(indexPathsOfDeletedRows: bufferingChanges!.flatMap { $0.indexPathsOfDeletedRows ?? [] },
				indexPathsOfInsertedRows: bufferingChanges!.flatMap { $0.indexPathsOfInsertedRows ?? [] },
				indexPathsOfMovedRows: bufferingChanges!.flatMap { $0.indexPathsOfMovedRows ?? [] },
				indexPathsOfUpdatedRows: bufferingChanges!.flatMap { $0.indexPathsOfUpdatedRows ?? [] })

			eventObserver.sendNext(.Updated(changes))
		}

		bufferingChanges = nil
	}

	public func pushChanges(changes: ReactiveSetEvent.Changes) {
		if bufferingChanges != nil {
			bufferingChanges!.append(changes)
		} else {
			eventObserver.sendNext(.Updated(changes))
		}
	}

	deinit {
		eventObserver.sendCompleted()
	}
}

extension ArraySetSection: ReactiveSetSection, MutableCollectionType {
	public typealias Index = Int
	public typealias Generator = AnyReactiveSetSectionIterator<E>

	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public func generate() -> AnyReactiveSetSectionIterator<E> {
		var index = storage.startIndex
		let limit = storage.endIndex

		return AnyReactiveSetSectionIterator {
			defer { index = index.successor() }
			return index < limit ? self.storage[index] : nil
		}
	}

	public subscript(position: Int) -> E {
		get {
			return storage[position]
		}
		set(newValue) {
			storage[position] = newValue
			pushChanges(ReactiveSetEvent.Changes(indexPathsOfUpdatedRows: [NSIndexPath(index: position)]))
		}
	}

	public subscript(bounds: Range<Int>) -> ArraySlice<E> {
		get {
			return storage[bounds]
		}
		set {
			storage.replaceRange(bounds, with: Array(newValue))
		}
	}
}

extension ArraySetSection: RangeReplaceableCollectionType {
	public convenience init() {
		self.init(name: ReactiveSetSectionName(), values: [])
	}

	public func append(newElement: Generator.Element) {
		replaceRange(endIndex ..< endIndex, with: [newElement])
	}

	public func appendContentsOf<S : SequenceType where S.Generator.Element == Generator.Element>(newElements: S) {
		let elements =  Array(newElements)
		if !elements.isEmpty {
			replaceRange(endIndex ..< endIndex, with: elements)
		}
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
		storage.replaceRange(subRange, with: newElements)

		let newEndIndex = subRange.startIndex + Int(newElements.count.toIntMax())

		if subRange.count == 0 {
			// Appending at subRange.startIndex, No Replacing & Deletion
			let indexPaths = (subRange.startIndex ..< newEndIndex).map {
				NSIndexPath(index: $0)
			}
			let changes = ReactiveSetEvent.Changes(indexPathsOfInsertedRows: indexPaths)
			pushChanges(changes)
		} else {
			let replacingEndIndex = min(newEndIndex, subRange.endIndex)
			let updatedRows = (subRange.startIndex ..< replacingEndIndex).map {
				NSIndexPath(index: $0)
			}

			var insertedRows: [NSIndexPath]?
			var deletedRows: [NSIndexPath]?

			if newEndIndex > subRange.endIndex {
				// Appending after replaced items
				insertedRows = (subRange.endIndex ..< newEndIndex).map {
					NSIndexPath(index: $0)
				}
			} else {
				// Deleting after replaced items
				deletedRows = (newEndIndex ..< subRange.endIndex).map {
					NSIndexPath(index: $0)
				}
			}

			let changes = ReactiveSetEvent.Changes(indexPathsOfDeletedRows: deletedRows ?? [],
				indexPathsOfInsertedRows: insertedRows ?? [],
				indexPathsOfUpdatedRows: updatedRows)

			pushChanges(changes)
		}
	}

	public func reserveCapacity(n: Index.Distance) {
		storage.reserveCapacity(n)
	}
}

extension ArraySetSection: Equatable {}

public func ==<E>(lhs: ArraySetSection<E>, rhs: ArraySetSection<E>) -> Bool {
	return lhs === rhs
}