//
//  ObjectCollectionPrefetcher.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import CoreData

/// ObjectCollection Prefetcher
public enum ObjectCollectionPrefetchingPolicy {
	case none
	case all
	case adjacent(batchSize: Int)
}

internal class ObjectCollectionPrefetcher<E: NSManagedObject> {
	func reset() {
		_abstractMethod_subclassMustImplement()
	}

	func acknowledgeNextAccess(at position: ObjectCollection<E>._IndexPath) {
		_abstractMethod_subclassMustImplement()
	}

	func acknowledgeFetchCompletion(_ objectCount: Int) {
		_abstractMethod_subclassMustImplement()
	}

	func acknowledgeChanges(inserted insertedIds: [SectionKey: Box<Set<NSManagedObjectID>>], deleted deletedIds: [Box<Set<NSManagedObjectID>>]) {
		_abstractMethod_subclassMustImplement()
	}
}


/// LinearBatchingPrefetcher
private enum LastUsedPool {
	case first
	case second
}

internal final class LinearBatchingPrefetcher<E: NSManagedObject>: ObjectCollectionPrefetcher<E> {
	weak var objectSet: ObjectCollection<E>!
	private var firstPool: [E]?
	private var secondPool: [E]?
	private var nextPool: LastUsedPool

	private let batchSize: Int
	private let halfOfBatch: Int

	var lastAccessedIndex: Int
	var prefetchedRange: CountableRange<Int>

	init(for objectSet: ObjectCollection<E>, batchSize: Int) {
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

	func flattenedIndex(at position: ObjectCollection<E>._IndexPath) -> Int? {
		guard position.section < objectSet.count else {
			return nil
		}

		var flattenedIndex = 0
		for index in 0 ..< position.section {
			flattenedIndex += objectSet.sections[index].count
		}
		return flattenedIndex + position.row
	}

	func expandedIndices(at flattenedPosition: Int) -> (section: Int, row: Int)? {
		if flattenedPosition < 0 {
			return nil
		}

		var remaining = flattenedPosition

		for index in objectSet.sections.indices {
			let count = objectSet.sections[index].count

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
			return (section: objectSet.sections.endIndex - 1,
							row: objectSet.sections[objectSet.sections.endIndex - 1].endIndex - 1)
		} else {
			return (section: 0, row: 0)
		}
	}

	func obtainIDsForBatch(at flattenedPosition: Int, forward isForwardPrefetching: Bool) -> [NSManagedObjectID] {
		var prefetchingIds = [ArraySlice<NSManagedObjectID>]()

		var (iteratingSectionIndex, iteratingPosition) = expandedIndicesWithCapping(at: flattenedPosition,
		                                                                            forForwardPrefetching: isForwardPrefetching)
		var delta = halfOfBatch
		let sectionIndices = objectSet.sections.indices

		while delta != 0 &&
					sectionIndices.contains(iteratingSectionIndex) &&
					iteratingPosition >= objectSet.sections[iteratingSectionIndex].startIndex {
			if isForwardPrefetching {
				let sectionEndIndex = objectSet.sections[iteratingSectionIndex].storage.endIndex
				let endIndex = objectSet.sections[iteratingSectionIndex].index(iteratingPosition,
				                                                               offsetBy: delta,
				                                                               limitedBy: sectionEndIndex) ?? sectionEndIndex
				delta = delta - (endIndex - iteratingPosition)

				let range = iteratingPosition ..< endIndex
				let slice = objectSet.sections[iteratingSectionIndex].storage[range]
				prefetchingIds.append(slice)
			} else {
				let sectionStartIndex = objectSet.sections[iteratingSectionIndex].storage.startIndex
				let startIndex = objectSet.sections[iteratingSectionIndex].index(iteratingPosition,
				                                                                 offsetBy: -delta,
				                                                                 limitedBy: sectionStartIndex) ?? sectionStartIndex
				delta = delta - (iteratingPosition - startIndex)

				let range = startIndex ..< iteratingPosition
				let slice = objectSet.sections[iteratingSectionIndex].storage[range]
				prefetchingIds.append(slice)
			}

			iteratingSectionIndex += isForwardPrefetching ? 1 : -1

			if iteratingSectionIndex >= objectSet.sections.startIndex {
				iteratingPosition = isForwardPrefetching ? 0 : objectSet.sections[iteratingSectionIndex].endIndex
			}
		}

		return prefetchingIds.flatMap { $0 }
	}

	func prefetch(at flattenedPosition: Int, forward isForwardPrefetching: Bool) throws {
		let prefetchingIds = obtainIDsForBatch(at: flattenedPosition,
		                                       forward: isForwardPrefetching)

		let prefetchRequest = NSFetchRequest<E>()
		prefetchRequest.entity = E.entity(in: objectSet.context)
		prefetchRequest.predicate = NSPredicate(format: "self IN %@",
		                                        argumentArray: [prefetchingIds as NSArray])
		prefetchRequest.resultType = NSFetchRequestResultType()
		prefetchRequest.returnsObjectsAsFaults = false

		let prefetchedObjects = try objectSet.context.fetch(prefetchRequest)
		retain(prefetchedObjects)
	}

	func retain(_ objects: [E]) {
		switch nextPool {
		case .first:
			firstPool = objects
			nextPool = .second
		case .second:
			secondPool = objects
			nextPool = .first
		}
	}

	override func acknowledgeNextAccess(at position: ObjectCollection<E>._IndexPath) {
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
			print("LinearBatchingPrefetcher<\(String(describing: E.self))>: cannot execute batch of prefetch at row \(position.row) in section \(position.section). Error: \(error)")
		}
	}

	override func acknowledgeFetchCompletion(_ objectCount: Int) {}
	override func acknowledgeChanges(inserted insertedIds: [SectionKey: Box<Set<NSManagedObjectID>>], deleted deletedIds: [Box<Set<NSManagedObjectID>>]) {}
}

/// GreedyPrefetcher

internal final class GreedyPrefetcher<E: NSManagedObject>: ObjectCollectionPrefetcher<E> {
	var retainingPool = Set<NSManagedObject>()
	unowned var objectSet: ObjectCollection<E>

	init(for objectSet: ObjectCollection<E>) {
		self.objectSet = objectSet
	}

	override func reset() {}
	override func acknowledgeNextAccess(at position: ObjectCollection<E>._IndexPath) {}

	override func acknowledgeFetchCompletion(_ objectCount: Int) {
		var ids = [NSManagedObjectID]()
		ids.reserveCapacity(objectCount)

		for index in objectSet.sections.indices {
			ids.append(contentsOf: objectSet.sections[index].storage)
		}

		let prefetchRequest = NSFetchRequest<NSManagedObject>()
		prefetchRequest.entity = E.entity(in: objectSet.context)
		prefetchRequest.predicate = NSPredicate(format: "self IN %@",
		                                        argumentArray: [ids as NSArray])
		prefetchRequest.resultType = NSFetchRequestResultType()

		do {
			let prefetchedObjects = try objectSet.context.fetch(prefetchRequest)
			retainingPool.formUnion(prefetchedObjects)
		} catch let error {
			print("GreedyPrefetcher<\(String(describing: E.self))>: cannot execute a prefetch. Error: \(error)")
		}
	}

	override func acknowledgeChanges(inserted insertedIds: [SectionKey: Box<Set<NSManagedObjectID>>], deleted deletedIds: [Box<Set<NSManagedObjectID>>]) {
		for ids in deletedIds {
			for id in ids.value {
				retainingPool.remove(objectSet.context.object(with: id))
			}
		}

		let insertedIds = insertedIds.flatMap { $0.1.value }

		if !insertedIds.isEmpty {
			let prefetchRequest = NSFetchRequest<NSManagedObject>()
			prefetchRequest.entity = E.entity(in: objectSet.context)
			prefetchRequest.predicate = NSPredicate(format: "self IN %@",
																							argumentArray: [insertedIds as NSArray])
			prefetchRequest.resultType = NSFetchRequestResultType()

			do {
				let prefetchedObjects = try objectSet.context.fetch(prefetchRequest)
				retainingPool.formUnion(prefetchedObjects)
			} catch let error {
				print("GreedyPrefetcher<\(String(describing: E.self))>: cannot execute a prefetch. Error: \(error)")
			}
		}
	}
}
