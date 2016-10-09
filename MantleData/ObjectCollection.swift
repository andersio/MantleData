//
//  ObjectCollection.swift
//  MantleData
//
//  Created by Anders on 9/9/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import CoreData
import ReactiveSwift
import enum Result.NoError

/// `ObjectCollection` manages a live-updated collection of managed objects
/// contrained by the supplied fetch request.
///
/// # Caveats
///
/// 1. Sorting and grouping supports one-level indirect key paths.
///
/// 2. By default, updated rows are not included in the changes notification.
///    Observe the object directly, or override the default of
///    `shouldExcludeUpdatedRows` in the initializer.
///
/// # Live Updating
///
/// `ObjectCollection` incorporates in-memory changes at best effort.
///
/// The collection is always up-to-date, except if its predicate evaluates any
/// indirect key paths. `ObjectCollection` cannot observe changes in attributes
/// of relationships that affect the predications. The collection has to be
/// reloaded in the circumstance.
///
/// # Using with a child managed object context
///
/// When using in a child context, the creation of permanent IDs of the inserted
/// objects must be forced before the child context is saved. A fatal error is 
/// raised if any inserted objects with temporary IDs is caught by the
/// `ObjectCollection`.
///
/// - warning: This class is not thread-safe. Use it only in the associated
///            managed object context.
public final class ObjectCollection<E: NSManagedObject> {
	internal typealias _IndexPath = IndexPath

	private let lifetimeToken = Lifetime.Token()
	public let lifetime: Lifetime

	public let fetchRequest: NSFetchRequest<NSDictionary>
	public let entity: NSEntityDescription

	public let shouldExcludeUpdatedRows: Bool
	public let sectionNameKeyPath: String?

	private(set) public weak var context: NSManagedObjectContext!

	internal var sections: [ObjectCollectionSection<E>] = []
	internal var prefetcher: ObjectCollectionPrefetcher<E>?

	private let predicate: NSPredicate

	private let sectionNameOrdering: ComparisonResult
	fileprivate let objectSortDescriptors: [NSSortDescriptor]
	private let sortKeys: [String]
	private let sortKeyComponents: [(String, [String])]
	private let sortOrderAffectingRelationships: [String]
	private let sortKeysInSections: [String]

	fileprivate var objectCache = [NSManagedObjectID: [String: NSObject]]()

	private var temporaryObjects = [E: NSManagedObjectID]()
	private var isAwaitingContextSave = false

	public let events: Signal<SectionedCollectionEvent, NoError>
	private var eventObserver: Observer<SectionedCollectionEvent, NoError>

	public private(set) var hasFetched: Bool = false

	public init(for fetchRequest: NSFetchRequest<E>,
							in context: NSManagedObjectContext,
							prefetchingPolicy: ObjectCollectionPrefetchingPolicy,
							sectionNameKeyPath: String? = nil,
							excludeUpdatedRowsInEvents: Bool = true) {
		(events, eventObserver) = Signal.pipe()
		lifetime = Lifetime(lifetimeToken)

		self.context = context
		self.entity = fetchRequest.entity!
		self.shouldExcludeUpdatedRows = excludeUpdatedRowsInEvents
		self.sectionNameKeyPath = sectionNameKeyPath

		precondition(fetchRequest.sortDescriptors != nil,
		             "ObjectCollection requires sort descriptors to work.")
		precondition(
			fetchRequest.sortDescriptors!.reduce(true) { reducedValue, descriptor in
				return reducedValue && descriptor.key!.components(separatedBy: ".").count <= 2
			},
			"ObjectCollection does not support sorting on to-one key paths deeper than 1 level."
		)

		if sectionNameKeyPath != nil {
			precondition(fetchRequest.sortDescriptors!.count >= 2,
			             "Unsufficient number of sort descriptors.")

			self.sectionNameOrdering = fetchRequest.sortDescriptors!.first!.ascending ? .orderedAscending : .orderedDescending
			self.objectSortDescriptors = Array(fetchRequest.sortDescriptors!.dropFirst())
		} else {
			self.sectionNameOrdering = .orderedSame
			self.objectSortDescriptors = fetchRequest.sortDescriptors ?? []
		}

		predicate = fetchRequest.predicate ?? NSPredicate(value: true)

		sortKeys = fetchRequest.sortDescriptors!.map { $0.key! }
		sortKeysInSections = Array(sortKeys.dropFirst())
		sortKeyComponents = sortKeys.map { ($0, $0.components(separatedBy: ".")) }
		sortOrderAffectingRelationships = sortKeyComponents.flatMap { $0.1.count > 1 ? $0.1[0] : nil }.uniquing()

		self.fetchRequest = fetchRequest.copy() as! NSFetchRequest<NSDictionary>
		self.fetchRequest.resultType = .dictionaryResultType

		let objectID = NSExpressionDescription()
		objectID.name = "objectID"
		objectID.expression = NSExpression.expressionForEvaluatedObject()
		objectID.expressionResultType = .objectIDAttributeType

		self.fetchRequest.propertiesToFetch = (sortOrderAffectingRelationships + sortKeys + [objectID]) as [Any]

		switch prefetchingPolicy {
		case let .adjacent(batchSize):
			prefetcher = LinearBatchingPrefetcher(for: self, batchSize: batchSize)

		case .all:
			prefetcher = GreedyPrefetcher(for: self)

		case .none:
			prefetcher = nil
		}

		NotificationCenter.default.reactive
			.notifications(forName: .NSManagedObjectContextObjectsDidChange,
			               object: context)
			.take(until: context.reactive.lifetime.ended.zip(with: lifetime.ended).map { _ in })
			.startWithValues(self.process(objectsDidChangeNotification:))
	}

	/// Fetch the objects and start the live updating.
	///
	/// The fetch is run synchronously by default, with the result being ready
	/// when the method returns.
	///
	/// If it is chosen to run asynchronously (`async == true`), the method
	/// returns right away after enqueuing the fetch. The result is ready at the
	/// time a `reloaded` event is observed.
	///
	/// - note: If the collection has been fetched, calling `fetch(async:)` again
	///         has no effects.
	///
	/// - parameters:
	///   - async: Whether the fetch should be run asynchronously.
	public func fetch(async: Bool = false) throws {
		guard !hasFetched else {
			return
		}

		hasFetched = true

		func completion(_ results: [NSDictionary]) {
			// Search inserted objects in the context.
			let inMemoryResults = context.insertedObjects
				.flatMap { object -> E? in
					if let object = object as? E, predicate.evaluate(with: object) {
						return object
					} else {
						return nil
					}
				}

			prefetcher?.reset()
			sectionize(using: results, inMemoryResults: inMemoryResults)
			prefetcher?.acknowledgeFetchCompletion(results.count)
			eventObserver.send(value: .reloaded)
		}

		do {
			if async {
				let asyncFetch = NSAsynchronousFetchRequest<NSDictionary>(fetchRequest: fetchRequest) { result in
					completion(result.finalResult ?? [])
				}
				try context.execute(asyncFetch)
			} else {
				let results = try context.fetch(fetchRequest)
				completion(results)
			}
		} catch let error {
			fatalError("\(error)")
		}
	}

	private func sectionize(using resultDictionaries: [NSDictionary], inMemoryResults: [E]) {
		sections = []

		if !resultDictionaries.isEmpty {
			var ranges: [(range: CountableRange<Int>, name: String?)] = []

			// Objects are sorted wrt sections already.
			for position in resultDictionaries.indices {
				if let sectionNameKeyPath = sectionNameKeyPath {
					let sectionName = converting(sectionName: resultDictionaries[position].object(forKey: sectionNameKeyPath as NSString) as! NSObject?)

					if ranges.isEmpty || ranges.last?.name != sectionName {
						ranges.append((range: position ..< position + 1, name: sectionName))
					} else {
						let range = ranges[ranges.endIndex - 1].range
						ranges[ranges.endIndex - 1].range = range.lowerBound ..< range.upperBound + 1
					}
				} else {
					if ranges.isEmpty {
						ranges.append((range: position ..< position + 1, name: nil))
					} else {
						let range = ranges[0].range
						ranges[0].range = range.lowerBound ..< range.upperBound + 1
					}
				}
			}

			sections.reserveCapacity(ranges.count)

			var inMemoryChangedObjects = [SectionKey: Set<NSManagedObjectID>]()

			func markAsChanged(object registeredObject: E) {
				updateCache(for: registeredObject.objectID, with: registeredObject)
				if let sectionNameKeyPath = sectionNameKeyPath {
					let sectionName = converting(sectionName: registeredObject.value(forKeyPath: sectionNameKeyPath) as! NSObject?)
					inMemoryChangedObjects.insert(registeredObject.objectID, intoSetOf: SectionKey(sectionName))
				} else {
					inMemoryChangedObjects.insert(registeredObject.objectID, intoSetOf: SectionKey(nil))
				}
			}

			for (range, name) in ranges {
				var objectIDs = ContiguousArray<NSManagedObjectID>()
				objectIDs.reserveCapacity(range.count)

				for position in range {
					let id = resultDictionaries[position]["objectID"] as! NSManagedObjectID

					// Deferred Insertion:
					//
					// An object may have indeterministic order with regard to a fetch
					// request result due to in-memory changes. In these cases, the
					// insertion would be deferred and handled with the changes merging
					// routine.

					// If the object is registered with the context, two special cases
					// require special handling:
					//
					// 1. If it has in-memory changes in the key paths affecting the sort
					//    order, the object cache is updated, but the insertion is
					//    deferred.
					//
					// 2. If the in-memory state fails the predicate, or it has been
					//    deleted, the object is ignored.
					if let registeredObject = context.registeredObject(for: id) as? E {
						let changedKeys = registeredObject.changedValues().keys
						let sortOrderIsAffected = sortKeyComponents.contains { changedKeys.contains($0.1[0]) }

						guard predicate.evaluate(with: registeredObject) && !registeredObject.isDeleted else {
							continue
						}

						if sortOrderIsAffected {
							markAsChanged(object: registeredObject)
							continue
						}
					}

					// If the sort order affecting relationships of the object are
					// registered with the context and has in-memory changes, the object
					// is faulted in and the object cache is updated subsequently. But the
					// insertion is deferred.
					let hasUpdatedRelationships = sortOrderAffectingRelationships.contains { key in
						if let relationshipID = resultDictionaries[position][key] as? NSManagedObjectID,
						   let relatedObject = context.registeredObject(for: relationshipID),
						   relatedObject.isUpdated {
							return true
						}
						return false
					}

					if hasUpdatedRelationships {
						let object = context.object(with: id) as! E
						markAsChanged(object: object)
						continue
					}

					/// Use the results in the dictionary to update the cache.
					updateCache(for: id, with: resultDictionaries[position])
					objectIDs.append(id)
				}

				let section = ObjectCollectionSection(at: sections.count, name: name, array: objectIDs, in: self)
				sections.append(section)
			}

			if !inMemoryResults.isEmpty || !inMemoryChangedObjects.isEmpty {
				for result in inMemoryResults {
					markAsChanged(object: result)
					registerTemporaryObject(result)
				}

				_ = mergeChanges(inserted: inMemoryChangedObjects,
				                 deleted: [],
				                 updated: [],
				                 sortOrderAffecting: [],
				                 sectionChanged: [])
			}
		}
	}

	@inline(__always)
	private func registerTemporaryObject(_ object: E) {
		temporaryObjects[object] = object.objectID

		if !isAwaitingContextSave {
			NotificationCenter.default
				.reactive
				.notifications(forName: NSNotification.Name.NSManagedObjectContextDidSave, object: context)
				.take(first: 1)
				.startWithValues(handle(contextDidSaveNotification:))

			isAwaitingContextSave = true
		}
	}

	@objc private func handle(contextDidSaveNotification notification: Notification) {
		guard let userInfo = (notification as NSNotification).userInfo else {
			return
		}

		if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
			for object in insertedObjects {
				guard let object = object as? E else {
					continue
				}

				if let temporaryId = temporaryObjects[object] {
					if !object.objectID.isTemporaryID {
						/// If the object ID is no longer temporary, find the position of the object.
						/// Then update the object and the cache with the permanent ID.

						let sectionIndex = sections.index(of: sectionName(of: object)!)!
						let objectIndex = sections[sectionIndex].storage.index(of: temporaryId,
																																	 using: objectSortDescriptors,
																																	 with: objectCache)!

						sections[sectionIndex].storage[objectIndex] = object.objectID
						clearCache(for: temporaryId)
						updateCache(for: object.objectID, with: object)
					} else {
						fatalError("ObjectCollection does not implement any workaround to the temporary ID issue with parent-child context relationships. Please use `NSManagedObjectContext.obtainPermanentIDsForObjects(_:)` before saving your objects in a child context.")
					}
				}
			}
		}

		temporaryObjects = [:]
		isAwaitingContextSave = false
	}

	private func updateCache(for objectID: NSManagedObjectID, with object: NSObject) {
		var dictionary = [String: NSObject]()

		for sortKey in sortKeys {
			dictionary[sortKey] = (object.value(forKeyPath: sortKey) as? NSObject) ?? NSNull()
		}

		objectCache[objectID] = dictionary
	}

	private func clearCache(for objectID: NSManagedObjectID) {
		objectCache.removeValue(forKey: objectID)
	}

	private func converting(sectionName: NSObject?) -> String? {
		guard let sectionName = sectionName else {
			return nil
		}

		switch sectionName {
		case let sectionName as NSString:
			return sectionName as String

		case let sectionName as NSNumber:
			return sectionName.stringValue

		case is NSNull:
			return nil

		default:
			assertionFailure("Unsupported section name data type.")
			return nil
		}
	}

	fileprivate func sectionName(of object: E) -> String? {
		if let keyPath = self.sectionNameKeyPath {
			let object = object.value(forKeyPath: keyPath) as! NSObject?
			return converting(sectionName: object)
		}

		return nil
	}

	/// - Returns: A qualifying object for `self`. `nil` if the object is not qualified.
	private func qualifyingObject(_ object: NSManagedObject) -> E? {
		if let object = object as? E {
			if predicate.evaluate(with: object) {
				return object
			}
		}
		return nil
	}

	private func sortOrderIsAffected(by object: E, comparingWithSnapshotAt objectCacheIndex: DictionaryIndex<NSManagedObjectID, [String: NSObject]>) -> Bool {
		let snapshot = objectCache[objectCacheIndex].1

		for key in sortKeysInSections {
			if let index = snapshot.index(forKey: key) {
				let value = object.value(forKeyPath: key) as! NSObject
				if !value.isEqual(snapshot[index].1) {
					return true
				}
			}
		}

		return false
	}

	private func processDeletedObjects(_ set: Set<NSManagedObject>,
															 deleted deletedIndexPaths: inout [[Int]],
															 cacheClearing cacheClearingIds: inout ContiguousArray<NSManagedObjectID>) {
		for object in set {
			guard let object = object as? E else {
				continue
			}

			if let cacheIndex = objectCache.index(forKey: object.objectID) {
				let sectionName: String?

				if let sectionNameKeyPath = sectionNameKeyPath {
					sectionName = converting(sectionName: objectCache[cacheIndex].1[sectionNameKeyPath])
				} else {
					sectionName = nil
				}

				if let index = sections.index(of: sectionName) {
					if let objectIndex = sections[index].storage.index(of: object.objectID,
					                                                   using: objectSortDescriptors,
					                                                   with: objectCache) {
						deletedIndexPaths.orderedInsert(objectIndex, toCollectionAt: index, ascending: false)
						cacheClearingIds.append(object.objectID)
					}
				}
			}
		}
	}

	private func processUpdatedObjects(_ set: Set<NSManagedObject>,
															 inserted insertedIds: inout [SectionKey: Set<NSManagedObjectID>],
															 updated updatedIds: inout [Set<NSManagedObjectID>],
															 sortOrderAffecting sortOrderAffectingIndexPaths: inout [Set<Int>],
															 sectionChanged sectionChangedIndexPaths: inout [Set<Int>],
															 deleted deletedIndexPaths: inout [[Int]],
															 cacheClearing cacheClearingIds: inout ContiguousArray<NSManagedObjectID>) {
		for object in set {
			guard let object = object as? E else {
				continue
			}

			let cacheIndex = objectCache.index(forKey: object.objectID)

			if !predicate.evaluate(with: object) {
				guard let cacheIndex = cacheIndex else {
					continue
				}

				/// The object no longer qualifies. Delete it from the ObjectCollection.
				let sectionName: String?

				if let sectionNameKeyPath = sectionNameKeyPath {
					sectionName = converting(sectionName: objectCache[cacheIndex].1[sectionNameKeyPath])
				} else {
					sectionName = nil
				}

				if let index = sections.index(of: sectionName) {
					/// Use binary search, but compare against the previous values dictionary.
					if let objectIndex = sections[index].storage.index(of: object.objectID,
					                                                   using: objectSortDescriptors,
					                                                   with: objectCache) {
						deletedIndexPaths.orderedInsert(objectIndex, toCollectionAt: index)
						cacheClearingIds.append(object.objectID)
						continue
					}
				}
			} else if let cacheIndex = cacheIndex {
				/// The object still qualifies. Does it have any change affecting the sort order?
				let currentSectionName: String?

				if let sectionNameKeyPath = sectionNameKeyPath {
					let previousSectionName = converting(sectionName: objectCache[cacheIndex].1[sectionNameKeyPath])
					currentSectionName = sectionName(of: object)

					guard previousSectionName == currentSectionName else {
						guard let previousSectionIndex = sections.index(of: currentSectionName) else {
							preconditionFailure("current section name is supposed to exist, but not found.")
						}

						guard let objectIndex = sections[previousSectionIndex].storage.index(of: object.objectID,
						                                                                     using: objectSortDescriptors,
						                                                                     with: objectCache) else {
							preconditionFailure("An object should be in section \(previousSectionIndex), but it cannot be found. (ID: \(object.objectID.uriRepresentation()))")
						}

						sectionChangedIndexPaths.insert(objectIndex, intoSetAt: previousSectionIndex)
						updateCache(for: object.objectID, with: object)
						continue
					}
				} else {
					currentSectionName = nil
				}

				guard let currentSectionIndex = sections.index(of: currentSectionName) else {
					preconditionFailure("current section name is supposed to exist, but not found.")
				}

				guard !sortOrderIsAffected(by: object, comparingWithSnapshotAt: cacheIndex) else {
					guard let objectIndex = sections[currentSectionIndex].storage.index(of: object.objectID,
					                                                                    using: objectSortDescriptors,
					                                                                    with: objectCache) else {
						preconditionFailure("An object should be in section \(currentSectionIndex), but it cannot be found. (ID: \(object.objectID.uriRepresentation()))")
					}

					sortOrderAffectingIndexPaths.insert(objectIndex, intoSetAt: currentSectionIndex)
					updateCache(for: object.objectID, with: object)
					continue
				}
				
				if !shouldExcludeUpdatedRows {
					updatedIds.insert(object.objectID, intoSetAt: currentSectionIndex)
				}
			} else {
				let currentSectionName = sectionName(of: object)
				insertedIds.insert(object.objectID, intoSetOf: SectionKey(currentSectionName))
				updateCache(for: object.objectID, with: object)
				continue
			}
		}
	}

	/// Merge changes since last posting of NSManagedContextObjectsDidChangeNotification.
	/// This method should not mutate the `sections` array.
	@objc private func process(objectsDidChangeNotification notification: Notification) {
		guard hasFetched else {
			return
		}

		guard let userInfo = (notification as NSNotification).userInfo else {
			return
		}

		/// If all objects are invalidated. We perform a refetch instead.
		guard !userInfo.keys.contains(NSInvalidatedAllObjectsKey) else {
			hasFetched = false
			try! fetch()
			return
		}

		/// Reference sections by name, since these objects may lead to creating a new section.
		var insertedIds = [SectionKey: Set<NSManagedObjectID>]()

		/// Referencing sections by the index in snapshot.
		var sectionChangedIndexPaths = sections.indices.map { _ in Set<Int>() }
		var deletedIndexPaths = sections.indices.map { _ in [Int]() }
		var updatedIds = sections.indices.map { _ in Set<NSManagedObjectID>() }
		var sortOrderAffectingIndexPaths = sections.indices.map { _ in Set<Int>() }
		var cacheClearingIds = ContiguousArray<NSManagedObjectID>()

		if let _insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
			var previouslyInsertedObjects = Set<NSManagedObject>()
			for object in _insertedObjects {
				if let object = qualifyingObject(object) {
					if objectCache.index(forKey: object.objectID) != nil {
						previouslyInsertedObjects.insert(object)
					} else {
						let name = sectionName(of: object)
						insertedIds.insert(object.objectID, intoSetOf: SectionKey(name))
						updateCache(for: object.objectID, with: object)

						if object.objectID.isTemporaryID {
							registerTemporaryObject(object)
						}
					}
				}
			}

			if !previouslyInsertedObjects.isEmpty {
				processUpdatedObjects(previouslyInsertedObjects,
				                      inserted: &insertedIds,
				                      updated: &updatedIds,
				                      sortOrderAffecting: &sortOrderAffectingIndexPaths,
				                      sectionChanged: &sectionChangedIndexPaths,
				                      deleted: &deletedIndexPaths,
				                      cacheClearing: &cacheClearingIds)
			}
		}

		if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
			processDeletedObjects(deletedObjects,
			                      deleted: &deletedIndexPaths,
			                      cacheClearing: &cacheClearingIds)
		}

		if let invalidatedObjects = userInfo[NSInvalidatedObjectsKey] as? Set<NSManagedObject> {
			processDeletedObjects(invalidatedObjects,
			                      deleted: &deletedIndexPaths,
			                      cacheClearing: &cacheClearingIds)
		}

		if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(updatedObjects,
			                      inserted: &insertedIds,
			                      updated: &updatedIds,
			                      sortOrderAffecting: &sortOrderAffectingIndexPaths,
			                      sectionChanged: &sectionChangedIndexPaths,
			                      deleted: &deletedIndexPaths,
			                      cacheClearing: &cacheClearingIds)
		}

		if let refreshedObjects = userInfo[NSRefreshedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(refreshedObjects,
			                      inserted: &insertedIds,
			                      updated: &updatedIds,
			                      sortOrderAffecting: &sortOrderAffectingIndexPaths,
			                      sectionChanged: &sectionChangedIndexPaths,
			                      deleted: &deletedIndexPaths,
			                      cacheClearing: &cacheClearingIds)
		}

		for id in cacheClearingIds {
			clearCache(for: id)
		}

		let changes = mergeChanges(inserted: insertedIds,
		                           deleted: deletedIndexPaths,
		                           updated: updatedIds,
		                           sortOrderAffecting: sortOrderAffectingIndexPaths,
		                           sectionChanged: sectionChangedIndexPaths)

		eventObserver.send(value: .updated(changes))
	}

	/// Merge the specific changes and compute the changes descriptor.
	///
	/// - parameters:
	///   - insertedObjects: Inserted object IDs for the affected sections.
	///   - deletedObjects: **Descending** indices of deleted objects in every
	///                     section.
	///   - updatedObjects: IDs of updated objects in every section.
	///   - sortOrderAffectingObjects: Indices of sort order affecting objects
	///                                in every section.
	///   - sectionChangedObjects: Indices of moving-across-sections objects in
	///                            every section.
	///
	/// - returns:
	///   The changes descriptor.
	private func mergeChanges(
		inserted insertedObjects: [SectionKey: Set<NSManagedObjectID>],
		deleted deletedObjects: [[Int]],
		updated updatedObjects: [Set<NSManagedObjectID>],
		sortOrderAffecting sortOrderAffectingObjects: [Set<Int>],
		sectionChanged sectionChangedObjects: [Set<Int>]
	) -> SectionedCollectionChanges {
		/// Process deletions first, and buffer moves and insertions.
		let sectionSnapshots = sections

		let insertedObjectsCount = insertedObjects.reduce(0) { $0 + $1.1.count }
		let deletedObjectsCount = deletedObjects.reduce(0) { $0 + $1.count }
		let sectionChangedObjectsCount = sectionChangedObjects.reduce(0) { $0 + $1.count }
		let updatedObjectsCount = updatedObjects.reduce(0) { $0 + $1.count }
		let sortOrderAffectingObjectsCount = sortOrderAffectingObjects.reduce(0) { $0 + $1.count }

		var inboundObjects = [SectionKey: Set<NSManagedObjectID>]()
		var inPlaceMovingObjects = sectionSnapshots.indices.map { _ in Set<NSManagedObjectID>() }
		var deletedObjects = deletedObjects

		var originOfSectionChangedObjects = [NSManagedObjectID: _IndexPath](minimumCapacity: sectionChangedObjectsCount)
		var originOfMovedObjects = [NSManagedObjectID: _IndexPath](minimumCapacity: sortOrderAffectingObjectsCount)

		var indexPathsOfInsertedRows = [_IndexPath]()
		var indexPathsOfUpdatedRows = [_IndexPath]()
		var indexPathsOfMovedRows = [(from: _IndexPath, to: _IndexPath)]()
		var indexPathsOfDeletedRows = [_IndexPath]()

		var indiceOfDeletedSections = IndexSet()
		var indiceOfInsertedSections = IndexSet()

		indexPathsOfInsertedRows.reserveCapacity(insertedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(sectionChangedObjectsCount + sortOrderAffectingObjectsCount)

		// Flatten objects that moved across sections into IndexPaths.
		for (previousSectionIndex, indices) in sectionChangedObjects.enumerated() {
			for previousObjectIndex in indices {
				let id = sectionSnapshots[previousSectionIndex].storage[previousObjectIndex]
				deletedObjects.orderedInsert(previousObjectIndex, toCollectionAt: previousSectionIndex, ascending: false)

				let indexPath = IndexPath(row: previousObjectIndex, section: previousSectionIndex)
				originOfSectionChangedObjects[id] = indexPath

				let newSectionName = sectionName(of: context.registeredObject(for: id) as! E)
				inboundObjects.insert(id, intoSetOf: SectionKey(newSectionName))
			}
		}

		// Flatten objects that moved within sections into IndexPaths.
		for (sectionIndex, indices) in sortOrderAffectingObjects.enumerated() {
			for previousObjectIndex in indices {
				let id = sectionSnapshots[sectionIndex].storage[previousObjectIndex]
				deletedObjects.orderedInsert(previousObjectIndex, toCollectionAt: sectionIndex, ascending: false)

				let indexPath = IndexPath(row: previousObjectIndex, section: sectionIndex)
				originOfMovedObjects[id] = indexPath

				inPlaceMovingObjects.insert(id, intoSetAt: sectionIndex)
			}
		}

		/// Notify the prefetcher for changes.
		prefetcher?.acknowledgeChanges(inserted: insertedObjects, deleted: deletedObjects)

		// Delete marked objects from the sections.
		for sectionIndex in deletedObjects.indices {
			deletedObjects[sectionIndex].forEach {
				sections[sectionIndex].storage.remove(at: $0)
			}
		}

		// Delete empty sections.
		for sectionIndex in sections.indices.reversed() {
			if sections[sectionIndex].count == 0 && inPlaceMovingObjects[sectionIndex].count == 0 {
				sections.remove(at: sectionIndex)
				indiceOfDeletedSections.insert(sectionIndex)
				deletedObjects.remove(at: sectionIndex)
			}
		}

		for (sectionIndex, rowIndice) in deletedObjects.enumerated() {
			for index in rowIndice {
				indexPathsOfDeletedRows.append(IndexPath(row: index, section: sectionIndex))
			}
		}

		/// MARK: Handle insertions.

		func insert(_ ids: Set<NSManagedObjectID>, intoSectionFor name: String?) {
			if let sectionIndex = sections.index(of: name) {
				for id in ids {
					sections[sectionIndex].storage.insert(id, using: objectSortDescriptors, with: objectCache)
				}
			} else {
				let section = ObjectCollectionSection(at: -1, name: name, array: ContiguousArray(ids), in: self)
				_ = sections.insert(section, name: name, ordering: sectionNameOrdering)
			}
		}

		for (sectionName, objects) in insertedObjects {
			insert(objects, intoSectionFor: sectionName.value)
		}

		for (sectionName, objects) in inboundObjects {
			insert(objects, intoSectionFor: sectionName.value)
		}

		/// MARK: Index generating full pass.

		for sectionIndex in sections.indices {
			let sectionName = sections[sectionIndex].name
			let previousSectionIndex = sectionSnapshots.index(of: sectionName)

			if let previousSectionIndex = previousSectionIndex {
				for id in inPlaceMovingObjects[previousSectionIndex] {
					sections[sectionIndex].storage.insert(id, using: objectSortDescriptors, with: objectCache)
				}
			} else {
				indiceOfInsertedSections.insert(sectionIndex)
			}

			let insertedObjects = insertedObjects[SectionKey(sectionName)] ?? []
			let inboundObjects = inboundObjects[SectionKey(sectionName)] ?? []

			for (objectIndex, object) in sections[sectionIndex].storage.enumerated() {
				// Emit index paths for updated rows, if enabled.
				if !shouldExcludeUpdatedRows {
					if let oldSectionIndex = previousSectionIndex,
					   updatedObjects[oldSectionIndex].contains(object) {
						let indexPath = _IndexPath(row: objectIndex, section: sectionIndex)
						indexPathsOfUpdatedRows.append(indexPath)
						continue
					}
				}

				// Insertions to existing sections.
				if previousSectionIndex != nil && insertedObjects.contains(object) {
					let indexPath = _IndexPath(row: objectIndex, section: sectionIndex)
					indexPathsOfInsertedRows.append(indexPath)
					continue
				}

				// Moved objects within the same section.
				if let indexPath = originOfMovedObjects[object] {
					let from = indexPath
					let to = _IndexPath(row: objectIndex, section: sectionIndex)
					indexPathsOfMovedRows.append((from, to))
					continue
				}

				// Moved objects across sections.
				if inboundObjects.contains(object) {
					let origin = originOfSectionChangedObjects[object]!

					if indiceOfDeletedSections.contains(origin.section) {
						/// The originated section no longer exists, treat it as an inserted row.
						let indexPath = _IndexPath(row: objectIndex, section: sectionIndex)
						indexPathsOfInsertedRows.append(indexPath)
						continue
					}

					if indiceOfInsertedSections.contains(sectionIndex) {
						/// The target section is newly created.
						continue
					}

					let to = _IndexPath(row: objectIndex, section: sectionIndex)
					indexPathsOfMovedRows.append((origin, to))
					continue
				}
			}
		}

		// Update the sections' `indexInSet`.
		for position in sections.indices {
			sections[position].indexInSet = position
		}

		let resultSetChanges: SectionedCollectionChanges
		resultSetChanges = SectionedCollectionChanges(
			deletedRows: indexPathsOfDeletedRows.isEmpty ? nil : indexPathsOfDeletedRows,
			insertedRows: indexPathsOfInsertedRows.isEmpty ? nil : indexPathsOfInsertedRows,
			movedRows: indexPathsOfMovedRows.isEmpty ? nil : indexPathsOfMovedRows,
			deletedSections: indiceOfDeletedSections.isEmpty ? nil : indiceOfDeletedSections,
			insertedSections: indiceOfInsertedSections.isEmpty ? nil : indiceOfInsertedSections
		)

		return resultSetChanges
	}

	deinit {
		eventObserver.sendCompleted()
	}
}

extension ObjectCollection: SectionedCollection {
	public typealias Index = IndexPath

	public var sectionCount: Int {
		return sections.count
	}

	public var startIndex: IndexPath {
		if sections.isEmpty {
			return IndexPath(row: 0, section: 0)
		}

		let start = sections.startIndex
		return IndexPath(row: sections[start].startIndex, section: start)
	}

	public var endIndex: IndexPath {
		return IndexPath(row: 0, section: sections.endIndex)
	}

	public var count: Int {
		return sections.reduce(0) { $0 + $1.count }
	}

	public func index(before i: IndexPath) -> IndexPath {
		precondition(i > startIndex)

		let section = sections[i.section]

		if let index = section.index(i.row,
		                             offsetBy: -1,
		                             limitedBy: section.startIndex
		) {
			return IndexPath(row: index, section: i.section)
		}

		if i.section == startIndex.section {
			preconditionFailure("Cannot advance beyond `startIndex`.")
		}

		let next = sections.index(i.section, offsetBy: -1)
		return IndexPath(row: sections[next].startIndex, section: next)
	}

	public func index(after i: IndexPath) -> IndexPath {
		precondition(i < endIndex)

		let section = sections[i.section]

		if let index = section.index(i.row,
		                             offsetBy: 1,
		                             limitedBy: section.index(before: section.endIndex)
		) {
			return IndexPath(row: index, section: i.section)
		}

		let next = sections.index(i.section, offsetBy: 1)
		if next == endIndex.section {
			return endIndex
		}

		return IndexPath(row: sections[next].startIndex, section: next)
	}

	public func distance(from start: IndexPath, to end: IndexPath) -> Int {
		let sectionDiff = end.section - start.section

		if sectionDiff == 0 {
			return end.row - start.row
		}

		if sectionDiff > 0 {
			let loopStart = sections.index(after: start.section)
			var count = (sections[start.section].endIndex - start.row) + end.row

			for i in loopStart ..< end.section {
				count += sections[i].count
			}

			return count
		} else {
			let loopStart = sections.index(after: end.section)
			var count = (start.row - sections[start.section].startIndex + 1) + (sections[end.section].endIndex - end.row)

			for i in loopStart ..< start.section {
				count += sections[i].count
			}

			return count
		}
	}
	
	public subscript(position: IndexPath) -> E {
		return sections[position.section][position.row]
	}

	public subscript(subRange: Range<IndexPath>) -> RandomAccessSlice<ObjectCollection<E>> {
		return RandomAccessSlice(base: self, bounds: subRange)
	}

	public func sectionName(for section: Int) -> String? {
		return sections[section].name
	}

	public func rowCount(for section: Int) -> Int {
		return sections[section].count
	}

	public func indexPath(of element: E) -> IndexPath? {
		let name = sectionName(of: element)
		if let sectionIndex = sections.index(of: name) {
			if let objectIndex = sections[sectionIndex].storage.index(
				of: element.objectID,
				using: objectSortDescriptors,
				with: objectCache
			) {
				return IndexPath(row: objectIndex, section: sectionIndex)
			}
		}

		return nil
	}
}

internal struct SectionKey: Hashable {
	let value: String?
	let hashValue: Int

	init(_ value: String?) {
		self.value = value
		self.hashValue = (value?.hashValue ?? -1) + 1
	}
}

internal func ==(left: SectionKey, right: SectionKey) -> Bool {
	return left.value == right.value
}

private protocol ObjectCollectionSectionProtocol {
	var name: String? { get }
}

internal struct ObjectCollectionSection<E: NSManagedObject>: BidirectionalCollection, ObjectCollectionSectionProtocol {
	typealias Index = Int

	let name: String?

	var indexInSet: Int
	var storage: ContiguousArray<NSManagedObjectID>
	unowned var parentSet: ObjectCollection<E>

	init(at index: Int, name: String?, array: ContiguousArray<NSManagedObjectID>?, in parentSet: ObjectCollection<E>) {
		self.indexInSet = index
		self.name = name
		self.storage = array ?? []
		self.parentSet = parentSet
	}

	var startIndex: Int {
		return 0
	}

	var endIndex: Int {
		return storage.count
	}

	subscript(position: Int) -> E {
		get {
			parentSet.prefetcher?.acknowledgeNextAccess(at: IndexPath(row: position, section: indexInSet))
			
			if let object = parentSet.context.registeredObject(for: storage[position]) as? E {
				return object
			}

			return parentSet.context.object(with: storage[position]) as! E
		}
		set { storage[position] = newValue.objectID }
	}

	subscript(subRange: Range<Int>) -> BidirectionalSlice<ObjectCollectionSection<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	func index(after i: Index) -> Index {
		return i + 1
	}

	func index(before i: Index) -> Index {
		return i - 1
	}
}

extension Collection where Iterator.Element: ObjectCollectionSectionProtocol {
	fileprivate func index(of name: String?) -> Index? {
		return index { String.compareSectionNames($0.name, with: name) == .orderedSame }
	}
}

extension RangeReplaceableCollection where Iterator.Element: ObjectCollectionSectionProtocol {
	mutating func insert(_ section: Iterator.Element,
	                              name: String?,
	                              ordering: ComparisonResult) -> Index {
		let position: Index
		if let searchResult = self.index(where: { String.compareSectionNames($0.name, with: name) != ordering }) {
			position = searchResult
		} else {
			position = ordering == .orderedAscending ? startIndex : endIndex
		}

		insert(section, at: position)
		return position
	}
}
