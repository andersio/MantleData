//
//  ObjectSet.swift
//  MantleData
//
//  Created by Anders on 9/9/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa
import CoreData

/// A controller which manages and tracks a reactive collection of `E`,
/// constrained by the supplied NSFetchRequest.
///
/// `ObjectSet` **does not support** sorting or section name on key paths that
/// are deeper than one level of one-to-one relationships.
///
/// As for observing changes of individual objects, `ObjectSet` by default does not emit any
/// index paths for updated rows based on the assumed use of KVO-based bindings. You may override
/// this behavior by setting `excludeUpdatedRowsInEvents` in the initialiser as `false`.
///
/// - Important: If you are using ObjectSet with a child context, you must force the creation of
///							 permanent IDs on inserted objects before you save a child context. Otherwise,
///							 ObjectSet would raise an assertion if it catches any inserted objects with
///							 temporary IDs having been saved.
///
/// - Warning:	 This class is not thread-safe. Use it only in the associated NSManagedObjectContext.
final public class ObjectSet<E: NSManagedObject>: Base {
	internal typealias _IndexPath = IndexPath

	public let fetchRequest: NSFetchRequest<NSDictionary>
	public let entity: NSEntityDescription

	public let shouldExcludeUpdatedRows: Bool
	public let sectionNameKeyPath: String?

	/*public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return SignalProducer { observer, disposable in
			if self.eventSignal == nil {
				let (signal, observer) = Signal<ReactiveSetEvent, NoError>.pipe()
				self.eventSignal = signal
				self.eventObserver = observer
			}

			disposable += self.eventSignal!.observe(observer)
		}
	}*/

	private(set) public weak var context: NSManagedObjectContext!

	internal var sections: [ObjectSetSection<E>] = []
	internal var prefetcher: ObjectSetPrefetcher<E>?

	private let sectionNameOrdering: ComparisonResult
	private let objectSortDescriptors: [SortDescriptor]
	private let sortKeys: [String]
	private let sortKeyComponents: [(String, [String])]
	private let sortOrderAffectingRelationships: [String]
	private let sortKeysInSections: [String]

	private var objectCache = [NSManagedObjectID: [String: AnyObject]]()

	private var temporaryObjects = [E: NSManagedObjectID]()
	private var isAwaitingContextSave = false

	public let events: Signal<SectionedCollectionEvent, NoError>
	private var eventObserver: Observer<SectionedCollectionEvent, NoError>

	private var isTracking: Bool = false {
		willSet {
			if !isTracking && newValue {
				NotificationCenter.default
					.rac_notifications(forName: .NSManagedObjectContextObjectsDidChange,
					                   object: context)
					.take(until: context.willDeinitProducer.zip(with: willDeinitProducer).map { _ in })
					.startWithNext(process(objectsDidChangeNotification:))
			}
		}
	}

	public init(for request: NSFetchRequest<E>,
							in context: NSManagedObjectContext,
							prefetchingPolicy: ObjectSetPrefetchingPolicy,
							sectionNameKeyPath: String? = nil,
							excludeUpdatedRowsInEvents: Bool = true) {
		(events, eventObserver) = Signal.pipe()
		self.context = context
		self.fetchRequest = request.copy() as! NSFetchRequest<NSDictionary>
		self.entity = self.fetchRequest.entity!

		self.shouldExcludeUpdatedRows = excludeUpdatedRowsInEvents

		self.sectionNameKeyPath = sectionNameKeyPath

		precondition(request.sortDescriptors != nil,
		             "ObjectSet requires sort descriptors to work.")
		precondition(request.sortDescriptors!.reduce(true) { reducedValue, descriptor in
			return reducedValue && descriptor.key!.components(separatedBy: ".").count <= 2
		}, "ObjectSet does not support sorting on to-one key paths deeper than 1 level.")

		if sectionNameKeyPath != nil {
			precondition(request.sortDescriptors!.count >= 2, "Unsufficient number of sort descriptors.")
			self.sectionNameOrdering = fetchRequest.sortDescriptors!.first!.ascending ? .orderedAscending : .orderedDescending
			self.objectSortDescriptors = Array(fetchRequest.sortDescriptors!.dropFirst())
		} else {
			self.sectionNameOrdering = .orderedSame
			self.objectSortDescriptors = fetchRequest.sortDescriptors ?? []
		}

		sortKeys = fetchRequest.sortDescriptors!.map { $0.key! }
		sortKeysInSections = Array(sortKeys.dropFirst())
		sortKeyComponents = sortKeys.map { ($0, $0.components(separatedBy: ".")) }
		sortOrderAffectingRelationships = sortKeyComponents.flatMap { $0.1.count > 1 ? $0.1[0] : nil }.uniquing()

		super.init()

		switch prefetchingPolicy {
		case let .adjacent(batchSize):
			prefetcher = LinearBatchingPrefetcher(for: self, batchSize: batchSize)

		case .all:
			prefetcher = GreedyPrefetcher(for: self)

		case .none:
			prefetcher = nil
		}
	}

	public func fetch(trackingChanges shouldTrackChanges: Bool = false) throws {
		if shouldTrackChanges && !isTracking {
			isTracking = true
		}

		let description = NSExpressionDescription()
		description.name = "objectID"
		description.expression = NSExpression.expressionForEvaluatedObject()
		description.expressionResultType = .objectIDAttributeType

		var fetching = [AnyObject]()

		fetching.append(description)
		fetching.append(contentsOf: sortOrderAffectingRelationships as [AnyObject])
		fetching.append(contentsOf: sortKeys.map { NSString(string: $0) })

		fetchRequest.propertiesToFetch = fetching
		fetchRequest.resultType = .dictionaryResultType

		do {
			let results = try context.fetch(fetchRequest)
			sectionize(using: results)
		} catch let error {
			fatalError("\(error)")
		}
	}

	private func sectionize(using resultDictionaries: [NSDictionary]) {
		sections = []
		prefetcher?.reset()

		if !resultDictionaries.isEmpty {
			var ranges: [(range: CountableRange<Int>, name: String?)] = []

			// Objects are sorted wrt sections already.
			for position in resultDictionaries.indices {
				if let sectionNameKeyPath = sectionNameKeyPath {
					let sectionName = converting(sectionName: resultDictionaries[position][sectionNameKeyPath])

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

			for (range, name) in ranges {
				var objectIDs = ContiguousArray<NSManagedObjectID>()
				objectIDs.reserveCapacity(range.count)

				for position in range {
					let id = resultDictionaries[position]["objectID"] as! NSManagedObjectID

					func markAsChanged(object registeredObject: E) {
						updateCache(for: registeredObject.objectID, with: registeredObject)
						if let sectionNameKeyPath = sectionNameKeyPath {
							let sectionName = converting(sectionName: registeredObject.value(forKeyPath: sectionNameKeyPath))
							inMemoryChangedObjects.insert(registeredObject.objectID, intoSetOf: SectionKey(sectionName))
						} else {
							inMemoryChangedObjects.insert(registeredObject.objectID, intoSetOf: SectionKey(nil))
						}
					}

					/// If an object is registered with the context and has changes in key paths affecting
					/// the sort order, update the cache but exclude the object from the set and handle it later.

					if let registeredObject = context.registeredObject(for: id) as? E {
						let changedKeys = registeredObject.changedValues().keys
						let sortOrderIsAffected = sortKeyComponents.contains { changedKeys.contains($0.1[0]) }

						if sortOrderIsAffected {
							markAsChanged(object: registeredObject)
							continue
						}
					}

					/// If an object itself is not registered with the context, but its relationships are and
					/// has changes, fault in the object, update the cache, then exclude the object from the set
					/// and handle it later.

					let hasUpdatedRelationships = sortOrderAffectingRelationships.contains { key in
						if let relationshipID = resultDictionaries[position][key] as? NSManagedObjectID,
							relatedObject = context.registeredObject(for: relationshipID) where relatedObject.isUpdated {
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

				let section = ObjectSetSection(at: sections.count, name: name, array: objectIDs, in: self)
				sections.append(section)
			}

			if !inMemoryChangedObjects.isEmpty {
				_ = mergeChanges(inserted: inMemoryChangedObjects)
			}
		}

		prefetcher?.acknowledgeFetchCompletion(resultDictionaries.count)
		eventObserver.sendNext(.reloaded)
	}

	private func registerTemporaryObject(_ object: E) {
		temporaryObjects[object] = object.objectID

		if !isAwaitingContextSave {
			NotificationCenter.default
				.rac_notifications(forName: NSNotification.Name.NSManagedObjectContextDidSave, object: context)
				.take(first: 1)
				.startWithNext(handle(contextDidSaveNotification:))

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
						assertionFailure("ObjectSet does not implement any workaround to the temporary ID issue with parent-child context relationships. Please use `NSManagedObjectContext.obtainPermanentIDsForObjects(_:)` before saving your objects in a child context.")
					}
				}
			}
		}

		temporaryObjects = [:]
		isAwaitingContextSave = false
	}

	private func updateCache(for objectID: NSManagedObjectID, with object: NSObject) {
		var dictionary = [String: AnyObject]()

		for sortKey in sortKeys {
			dictionary[sortKey] = object.value(forKeyPath: sortKey) ?? NSNull()
		}

		objectCache[objectID] = dictionary
	}

	private func clearCache(for objectID: NSManagedObjectID) {
		objectCache.removeValue(forKey: objectID)
	}

	private func converting(sectionName: AnyObject?) -> String? {
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

	private func _sectionName(of object: E) -> String? {
		if let keyPath = self.sectionNameKeyPath {
			let object = object.value(forKeyPath: keyPath)
			return converting(sectionName: object)
		}

		return nil
	}

	private func predicateMatching(_ object: NSObject) -> Bool {
		return fetchRequest.predicate?.evaluate(with: object) ?? true
	}

	/// - Returns: A qualifying object for `self`. `nil` if the object is not qualified.
	private func qualifyingObject(_ object: NSManagedObject) -> E? {
		if let object = object as? E {
			if predicateMatching(object) {
				return object
			}
		}
		return nil
	}

	private func sortOrderIsAffected(by object: E, comparingWithSnapshotAt objectCacheIndex: DictionaryIndex<NSManagedObjectID, [String: AnyObject]>) -> Bool {
		let snapshot = objectCache[objectCacheIndex].1

		for key in sortKeysInSections {
			if let index = snapshot.index(forKey: key) {
				if !object.value(forKeyPath: key)!.isEqual(snapshot[index].1) {
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
						deletedIndexPaths.orderedInsert(objectIndex, toCollectionAt: index)
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

			if !predicateMatching(object) {
				guard let cacheIndex = cacheIndex else {
					continue
				}

				/// The object no longer qualifies. Delete it from the ObjectSet.
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
					currentSectionName = _sectionName(of: object)

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
				let currentSectionName = _sectionName(of: object)
				insertedIds.insert(object.objectID, intoSetOf: SectionKey(currentSectionName))
				updateCache(for: object.objectID, with: object)
				continue
			}
		}
	}

	/// Merge changes since last posting of NSManagedContextObjectsDidChangeNotification.
	/// This method should not mutate the `sections` array.
	@objc private func process(objectsDidChangeNotification notification: Notification) {
		guard isTracking else {
			return
		}

		guard let userInfo = (notification as NSNotification).userInfo else {
			return
		}

		/// If all objects are invalidated. We perform a refetch instead.
		guard !userInfo.keys.contains(NSInvalidatedAllObjectsKey) else {
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
						let name = _sectionName(of: object)
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

		if let changes = mergeChanges(inserted: insertedIds,
																  deleted: deletedIndexPaths,
																  updated: updatedIds,
																  sortOrderAffecting: sortOrderAffectingIndexPaths,
																  sectionChanged: sectionChangedIndexPaths) {
			eventObserver.sendNext(.updated(changes))
		}
	}

	private func mergeChanges(inserted insertedObjects: [SectionKey: Set<NSManagedObjectID>]? = nil,
														deleted deletedObjects: [[Int]]? = nil,
														updated updatedObjects: [Set<NSManagedObjectID>]? = nil,
														sortOrderAffecting sortOrderAffectingObjects: [Set<Int>]? = nil,
														sectionChanged sectionChangedObjects: [Set<Int>]? = nil)
														-> SectionedCollectionChanges? {
		let insertedObjects = insertedObjects ?? [:]
		let sectionChangedObjects = sectionChangedObjects ?? sections.indices.map { _ in Set<Int>() }
		let deletedObjects = deletedObjects ?? sections.indices.map { _ in [Int]() }
		let updatedObjects = updatedObjects ?? sections.indices.map { _ in Set<NSManagedObjectID>() }
		let sortOrderAffectingObjects = sortOrderAffectingObjects ?? sections.indices.map { _ in Set<Int>() }

		/// Notify the prefetcher for changes.
		prefetcher?.acknowledgeChanges(inserted: insertedObjects, deleted: deletedObjects)

		/// Process deletions first, and buffer moves and insertions.
		let sectionSnapshots = sections

		let insertedObjectsCount = insertedObjects.reduce(0) { $0 + $1.1.count }
		let deletedObjectsCount = deletedObjects.reduce(0) { $0 + $1.count }
		let sectionChangedObjectsCount = sectionChangedObjects.reduce(0) { $0 + $1.count }
		let updatedObjectsCount = updatedObjects.reduce(0) { $0 + $1.count }
		let sortOrderAffectingObjectsCount = sortOrderAffectingObjects.reduce(0) { $0 + $1.count }

		var inboundObjects = [SectionKey: Set<NSManagedObjectID>]()
		var inPlaceMovingObjects = sectionSnapshots.indices.map { _ in Set<NSManagedObjectID>() }
		var deletingIndexPaths = (0 ..< sectionSnapshots.count).map { _ in [Int]() }

		var originOfSectionChangedObjects = [NSManagedObjectID: _IndexPath](minimumCapacity: sectionChangedObjectsCount)
		var originOfMovedObjects = [NSManagedObjectID: _IndexPath](minimumCapacity: sortOrderAffectingObjectsCount)

		var indexPathsOfInsertedRows = [_IndexPath]()
		var indexPathsOfUpdatedRows = [_IndexPath]()
		var indexPathsOfMovedRows = [(from: _IndexPath, to: _IndexPath)]()

		var indiceOfDeletedSections = IndexSet()
		var indiceOfInsertedSections = IndexSet()

		indexPathsOfInsertedRows.reserveCapacity(insertedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(sectionChangedObjectsCount + sortOrderAffectingObjectsCount)

		/// MARK: Handle deletions.

		deletedObjects.enumerated().forEach { sectionIndex, indices in
			indices.forEach { objectIndex in
				deletingIndexPaths.orderedInsert(objectIndex, toCollectionAt: sectionIndex, ascending: false)
			}
		}

		for (previousSectionIndex, indices) in sectionChangedObjects.enumerated() {
			for previousObjectIndex in indices {
				let id = sectionSnapshots[previousSectionIndex].storage[previousObjectIndex]
				deletingIndexPaths.orderedInsert(previousObjectIndex, toCollectionAt: previousSectionIndex, ascending: false)

				let indexPath = IndexPath(row: previousObjectIndex, section: previousSectionIndex)
				originOfSectionChangedObjects[id] = indexPath

				let newSectionName = _sectionName(of: context.registeredObject(for: id) as! E)
				inboundObjects.insert(id, intoSetOf: SectionKey(newSectionName))
			}
		}

		for (sectionIndex, indices) in sortOrderAffectingObjects.enumerated() {
			for previousObjectIndex in indices {
				let id = sectionSnapshots[sectionIndex].storage[previousObjectIndex]
				deletingIndexPaths.orderedInsert(previousObjectIndex, toCollectionAt: sectionIndex, ascending: false)

				let indexPath = IndexPath(row: previousObjectIndex, section: sectionIndex)
				originOfMovedObjects[id] = indexPath

				inPlaceMovingObjects.insert(id, intoSetAt: sectionIndex)
			}
		}

		for sectionIndex in deletingIndexPaths.indices {
			deletingIndexPaths[sectionIndex].forEach {
				sections[sectionIndex].storage.remove(at: $0)
			}
		}

		for index in sections.indices.reversed() {
			if sections[index].count == 0 && inPlaceMovingObjects[index].count == 0 {
				sections.remove(at: index)
				indiceOfDeletedSections.insert(index)
				deletingIndexPaths.remove(at: index)
			}
		}

		var indexPathsOfDeletedRows = deletingIndexPaths.enumerated().flatMap { sectionIndex, indices in
			return indices.map { IndexPath(row: $0, section: sectionIndex) }
		}

		/// MARK: Handle insertions.

		func insert(_ ids: Set<NSManagedObjectID>, intoSectionFor name: String?) {
			if let sectionIndex = sections.index(of: name) {
				for id in ids {
					sections[sectionIndex].storage.insert(id, using: objectSortDescriptors, with: objectCache)
				}
			} else {
				let section = ObjectSetSection(at: -1, name: name, array: ContiguousArray(ids), in: self)
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
				if !shouldExcludeUpdatedRows {
					if let oldSectionIndex = previousSectionIndex where updatedObjects[oldSectionIndex].contains(object) {
						let indexPath = _IndexPath(row: objectIndex, section: sectionIndex)
						indexPathsOfUpdatedRows.append(indexPath)
						continue
					}
				}

				if previousSectionIndex != nil && insertedObjects.contains(object) {
					let indexPath = _IndexPath(row: objectIndex, section: sectionIndex)
					indexPathsOfInsertedRows.append(indexPath)
					continue
				}

				if let indexPath = originOfMovedObjects[object] {
					let from = indexPath
					let to = _IndexPath(row: objectIndex, section: sectionIndex)
					indexPathsOfMovedRows.append((from, to))

					continue
				}

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

extension ObjectSet: SectionedCollection {
	public typealias Index = IndexPath

	public var sectionCount: Int {
		return sections.count
	}

	public var startIndex: IndexPath {
		let start = sections.startIndex
		return IndexPath(row: sections[start].startIndex, section: start)
	}

	public var endIndex: IndexPath {
		let end = sections.index(sections.endIndex, offsetBy: -1, limitedBy: sections.startIndex) ?? sections.startIndex
		return IndexPath(row: sections[end].endIndex, section: end)
	}

	public func index(before i: IndexPath) -> IndexPath {
		let section = sections[i.section]

		if let index = section.index(i.row,
		                             offsetBy: -1,
		                             limitedBy: section.startIndex
		) {
			return IndexPath(row: index, section: i.section)
		}

		return IndexPath(row: sections[i.section - 1].index(before: sections[i.section - 1].endIndex),
		                 section: i.section - 1)
	}

	public func index(after i: IndexPath) -> IndexPath {
		let section = sections[i.section]

		if let index = section.index(i.row,
		                             offsetBy: 1,
		                             limitedBy: section.index(before: section.endIndex)
		) {
			return IndexPath(row: index, section: i.section)
		}

		return IndexPath(row: sections[i.section + 1].startIndex, section: i.section + 1)
	}
	
	public subscript(position: IndexPath) -> E {
		return sections[position.section][position.row]
	}

	public subscript(subRange: Range<IndexPath>) -> RandomAccessSlice<ObjectSet<E>> {
		return RandomAccessSlice(base: self, bounds: subRange)
	}

	public func sectionName(for section: Int) -> String? {
		return sections[section].name
	}

	public func rowCount(for section: Int) -> Int {
		return sections[section].count
	}

	private func sectionName(of object: E) -> String? {
		return _sectionName(of: object)
	}

	public func indexPath(of element: E) -> IndexPath? {
		let sectionName = _sectionName(of: element)
		if let sectionIndex = sections.index(of: sectionName) {
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

private protocol ObjectSetSectionProtocol {
	var name: String? { get }
}

internal struct ObjectSetSection<E: NSManagedObject>: BidirectionalCollection, ObjectSetSectionProtocol {
	typealias Index = Int

	let name: String?

	var indexInSet: Int
	var storage: ContiguousArray<NSManagedObjectID>
	unowned var parentSet: ObjectSet<E>

	init(at index: Int, name: String?, array: ContiguousArray<NSManagedObjectID>?, in parentSet: ObjectSet<E>) {
		self.indexInSet = index
		self.name = name
		self.storage = array ?? []
		self.parentSet = parentSet
	}

	var startIndex: Int {
		return storage.startIndex
	}

	var endIndex: Int {
		return storage.endIndex
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

	subscript(subRange: Range<Int>) -> BidirectionalSlice<ObjectSetSection<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	func index(after i: Index) -> Index {
		return i + 1
	}

	func index(before i: Index) -> Index {
		return i - 1
	}
}

extension Collection where Iterator.Element: ObjectSetSectionProtocol {
	private func index(of name: String?) -> Index? {
		return index { String.compareSectionNames($0.name, with: name) == .orderedSame }
	}
}

extension RangeReplaceableCollection where Iterator.Element: ObjectSetSectionProtocol {
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
