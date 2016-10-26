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

private struct BatchingState<Element> {
	var seq = 0

	var removals: [Int] = []
	var insertions: [(index: Int?, value: Element)] = []
	var updates: Set<Int> = []
}

final public class ReactiveArray<E> {
	public var name: String? = nil

	public let events: Signal<SectionedCollectionEvent, NoError>
	fileprivate let eventObserver: Observer<SectionedCollectionEvent, NoError>

	fileprivate var storage: [E] = []

	private var batchingState: BatchingState<E>?

	public init<S: Sequence>(_ content: S) where S.Iterator.Element == E {
		(events, eventObserver) = Signal.pipe()
		storage = Array(content)
	}

	public required convenience init() {
		self.init([])
	}

	/// Batch mutations to the array for one collection changed event.
	///
	/// Removals respect the old indexes, while insertions and update respect
	/// the order after the removals are applied.
	///
	/// - parameters:
	///   - action: The action which mutates the array.
	public func batchUpdate(action: () -> Void) {
		batchingState = BatchingState()
		action()
		apply(batchingState!)
		batchingState = nil
	}

	private func apply(_ state: BatchingState<E>) {
		let removals = state.removals.sorted(by: >)
		var updates = state.updates.sorted(by: >)

		for index in removals {
			storage.remove(at: index)

			for i in updates.indices {
				if updates[i] < index {
					break
				} else {
					assert(updates[i] != index, "Attempt to update an element to be deleted.")
					updates[i] -= 1
				}
			}
		}

		let insertions = state.insertions
		var insertedRows = [Int]()
		insertedRows.reserveCapacity(insertions.count)

		for (index, value) in insertions {
			let index = index ?? storage.endIndex
			storage.insert(value, at: index)

			for i in insertedRows.indices {
				if insertedRows[i] >= index {
					insertedRows[i] += 1
				}
			}

			insertedRows.append(index)

			for i in updates.indices.reversed() {
				if updates[i] < index {
					break
				} else {
					assert(updates[i] != index, "Attempt to update a element to be inserted.")
					updates[i] += 1
				}
			}
		}

		let changes = SectionedCollectionChanges(deletedRows: removals.map { IndexPath(row: $0, section: 0) },
		                                         insertedRows: insertedRows.map { IndexPath(row: $0, section: 0) },
		                                         updatedRows: updates.map { IndexPath(row: $0, section: 0) })
		eventObserver.send(value: .updated(changes))
	}

	public func append(_ element: E) {
		_insert(element, at: nil)
	}

	public func insert(_ element: E, at index: Int) {
		_insert(element, at: index)
	}

	private func _insert(_ element: E, at index: Int?) {
		if batchingState == nil {
			let index = index ?? storage.endIndex
			storage.insert(element, at: index)

			let changes = SectionedCollectionChanges(insertedRows: [IndexPath(row: index, section: 0)])
			eventObserver.send(value: .updated(changes))
		} else {
			batchingState!.insertions.append((index, element))
		}
	}

	@discardableResult
	public func remove(at index: Int) -> E {
		if batchingState == nil {
			let value = storage.remove(at: index)

			let changes = SectionedCollectionChanges(deletedRows: [IndexPath(row: index, section: 0)])
			eventObserver.send(value: .updated(changes))

			return value
		} else {
			batchingState!.removals.append(index)
			return storage[index]
		}
	}

	public func move(elementAt index: Int, to newIndex: Int) {
		if batchingState == nil {
			let value = storage.remove(at: index)
			storage.insert(value, at: newIndex)

			let changes = SectionedCollectionChanges(movedRows: [(from: IndexPath(row: index, section: 0),
			                                                      to: IndexPath(row: newIndex, section: 0))])
			eventObserver.send(value: .updated(changes))
		} else {
			batchingState!.removals.append(index)
			batchingState!.insertions.append((newIndex, storage[index]))
		}
	}

	public subscript(position: Int) -> E {
		get {
			return storage[position]
		}
		set {
			storage[position] = newValue

			if batchingState == nil {
				let changes = SectionedCollectionChanges(updatedRows: [IndexPath(row: position, section: 0)])
				eventObserver.send(value: .updated(changes))
			} else {
				batchingState!.updates.insert(position)
			}
		}
	}

	deinit {
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
		assert(section == 0, "ReactiveArray supports only one section.")
		return storage[row]
	}

	public func sectionName(for section: Int) -> String? {
		return nil
	}

	public func rowCount(for section: Int) -> Int {
		return section > 0 ? 0 : storage.count
	}
}
