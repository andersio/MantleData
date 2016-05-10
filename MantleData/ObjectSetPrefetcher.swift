//
//  ObjectSetPrefetcher.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import CoreData

/// ObjectSet Prefetcher
public enum ObjectSetPrefetchingPolicy {
	case none
	case all
	case adjacent(batchSize: Int)
}

internal class ObjectSetPrefetcher<E: NSManagedObject> {
	func reset() {
		_abstractMethod_subclassMustImplement()
	}

	func acknowledgeNextAccess(at position: ObjectSet<E>._IndexPath) {
		_abstractMethod_subclassMustImplement()
	}

	func acknowledgeFetchCompletion(objectCount: Int) {
		_abstractMethod_subclassMustImplement()
	}

	func acknowledgeChanges(inserted insertedIds: [ReactiveSetSectionName: Set<NSManagedObjectID>], deleted deletedIds: [[Int]]) {
		_abstractMethod_subclassMustImplement()
	}
}


/// LinearBatchingPrefetcher
private enum LastUsedPool {
	case first
	case second
}

internal final class LinearBatchingPrefetcher<E: NSManagedObject>: ObjectSetPrefetcher<E> {
	weak var objectSet: ObjectSet<E>!
	private var firstPool: [E]?
	private var secondPool: [E]?
	private var nextPool: LastUsedPool

	private let batchSize: Int
	private let halfOfBatch: Int

	var lastAccessedIndex: Int
	var prefetchedRange: Range<Int>

	init(for objectSet: ObjectSet<E>, batchSize: Int) {
		assert(batchSize % 2 == 0)
		self.objectSet = objectSet
		self.batchSize = batchSize
		self.halfOfBatch = batchSize / 2

		self.lastAccessedIndex = -batchSize
		self.prefetchedRange = 0 ..< 0
		self.nextPool = .first
	}

	override func reset() {
		firstPool = nil
		secondPool = nil
		nextPool = .first
		prefetchedRange = 0 ..< 0
	}

	func flattenedIndex(at position: ObjectSet<E>._IndexPath) -> Int? {
		guard position.section < objectSet.count else {
			return nil
		}

		var flattenedIndex = 0
		for index in 0 ..< position.section {
			flattenedIndex += objectSet[index].count
		}
		return flattenedIndex + position.row
	}

	func expandedIndices(at flattenedPosition: Int) -> (section: Int, row: Int)? {
		if flattenedPosition < 0 {
			return nil
		}

		var remaining = flattenedPosition

		for index in objectSet.indices {
			let count = objectSet[index].count

			if count > 0 {
				if remaining >= count {
					remaining -= count
				} else {
					return (section: index, row: remaining)
				}
			}
		}

		return nil
	}

	func expandedIndicesWithCapping(at flattenedPosition: Int, forForwardPrefetching: Bool) -> (section: Int, row: Int) {
		if let indices = expandedIndices(at: flattenedPosition) {
			return indices
		}

		if forForwardPrefetching {
			return (section: objectSet.endIndex - 1, row: (objectSet.last?.endIndex ?? 0) - 1)
		} else {
			return (section: 0, row: 0)
		}
	}

	func obtainIDsForBatch(at flattenedPosition: Int, forward isForwardPrefetching: Bool) -> [NSManagedObjectID] {
		var prefetchingIds = [ArraySlice<NSManagedObjectID>]()

		var (iteratingSectionIndex, iteratingPosition) = expandedIndicesWithCapping(at: flattenedPosition,
		                                                                            forForwardPrefetching: isForwardPrefetching)
		var delta = halfOfBatch
		let sectionIndices = objectSet.indices

		while delta != 0 &&
					sectionIndices.contains(iteratingSectionIndex) &&
					iteratingPosition >= objectSet.sections[iteratingSectionIndex].startIndex {
			if isForwardPrefetching {
				let endIndex = iteratingPosition.advancedBy(delta,
				                                            limit: objectSet[iteratingSectionIndex].storage.endIndex)
				delta = delta - (endIndex - iteratingPosition)

				let range = iteratingPosition ..< endIndex
				let slice = objectSet[iteratingSectionIndex].storage[range]
				prefetchingIds.append(slice)
			} else {
				let startIndex = iteratingPosition.advancedBy(-delta,
				                                              limit: objectSet[iteratingSectionIndex].storage.startIndex)
				delta = delta - (iteratingPosition - startIndex)

				let range = startIndex ..< iteratingPosition
				let slice = objectSet[iteratingSectionIndex].storage[range]
				prefetchingIds.append(slice)
			}

			iteratingSectionIndex += isForwardPrefetching ? 1 : -1

			if iteratingSectionIndex >= objectSet.startIndex {
				iteratingPosition = isForwardPrefetching ? 0 : objectSet[iteratingSectionIndex].endIndex
			}
		}

		return prefetchingIds.flatMap { $0 }
	}

	func prefetch(at flattenedPosition: Int, forward isForwardPrefetching: Bool) throws {
		let prefetchingIds = obtainIDsForBatch(at: flattenedPosition,
		                                       forward: isForwardPrefetching)

		let prefetchRequest = NSFetchRequest(entityName: String(E))
		prefetchRequest.predicate = NSPredicate(format: "self IN %@",
		                                        argumentArray: [prefetchingIds as NSArray])
		prefetchRequest.resultType = .ManagedObjectResultType
		prefetchRequest.returnsObjectsAsFaults = false

		let prefetchedObjects = try objectSet.context.executeFetchRequest(prefetchRequest) as! [E]
		retain(prefetchedObjects)
	}

	func retain(objects: [E]) {
		switch nextPool {
		case .first:
			firstPool = objects
			nextPool = .second
		case .second:
			secondPool = objects
			nextPool = .first
		}
	}

	override func acknowledgeNextAccess(at position: ObjectSet<E>._IndexPath) {
		guard let currentPosition = flattenedIndex(at: position) else {
			return
		}

		defer {
			lastAccessedIndex = currentPosition
		}

		do {
			let isMovingForward = currentPosition - lastAccessedIndex >= 0

			if currentPosition % halfOfBatch == 0 && (currentPosition != 0 || isMovingForward) {
				try prefetch(at: currentPosition,
				             forward: isMovingForward)

				prefetchedRange = currentPosition - halfOfBatch + 1 ..< currentPosition + halfOfBatch
			}
		} catch let error {
			print("LinearBatchingPrefetcher<\(String(E))>: cannot execute batch of prefetch at row \(position.row) in section \(position.section). Error: \(error)")
		}
	}

	override func acknowledgeFetchCompletion(objectCount: Int) {}
	override func acknowledgeChanges(inserted insertedIds: [ReactiveSetSectionName: Set<NSManagedObjectID>], deleted deletedIds: [[Int]]) {}
}

/// GreedyPrefetcher

internal final class GreedyPrefetcher<E: NSManagedObject>: ObjectSetPrefetcher<E> {
	var retainingPool = Set<E>()
	unowned var objectSet: ObjectSet<E>

	init(for objectSet: ObjectSet<E>) {
		self.objectSet = objectSet
	}

	override func reset() {}
	override func acknowledgeNextAccess(at position: ObjectSet<E>._IndexPath) {}

	override func acknowledgeFetchCompletion(objectCount: Int) {
		var ids = [NSManagedObjectID]()
		ids.reserveCapacity(objectCount)

		for index in objectSet.indices {
			ids.appendContentsOf(objectSet[index].storage)
		}

		let prefetchRequest = NSFetchRequest(entityName: String(E))
		prefetchRequest.predicate = NSPredicate(format: "self IN %@",
		                                        argumentArray: [ids as NSArray])
		prefetchRequest.resultType = .ManagedObjectResultType

		do {
			let prefetchedObjects = try objectSet.context.executeFetchRequest(prefetchRequest) as! [E]
			retainingPool.unionInPlace(prefetchedObjects)
		} catch let error {
			print("GreedyPrefetcher<\(String(E))>: cannot execute a prefetch. Error: \(error)")
		}
	}

	override func acknowledgeChanges(inserted insertedIds: [ReactiveSetSectionName: Set<NSManagedObjectID>], deleted deletedIds: [[Int]]) {
		for (sectionIndex, objectIndices) in deletedIds.enumerate() {
			for index in objectIndices {
				retainingPool.remove(objectSet[sectionIndex][index])
			}
		}

		let insertedIds = insertedIds.flatMap { $0.1 }

		let prefetchRequest = NSFetchRequest(entityName: String(E))
		prefetchRequest.predicate = NSPredicate(format: "self IN %@",
		                                        argumentArray: [insertedIds as NSArray])
		prefetchRequest.resultType = .ManagedObjectResultType

		do {
			let prefetchedObjects = try objectSet.context.executeFetchRequest(prefetchRequest) as! [E]
			retainingPool.unionInPlace(prefetchedObjects)
		} catch let error {
			print("GreedyPrefetcher<\(String(E))>: cannot execute a prefetch. Error: \(error)")
		}
	}
}