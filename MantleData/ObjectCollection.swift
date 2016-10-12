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
	internal typealias Objects = Tree<ObjectNode<E>, (), ObjectComparer<E>>
	internal typealias Sections = Tree<String?, Objects, SectionComparer<E>>

	private let lifetimeToken = Lifetime.Token()
	public let lifetime: Lifetime

	public let fetchRequest: NSFetchRequest<NSDictionary>
	public let entity: NSEntityDescription

	public let shouldExcludeUpdatedRows: Bool
	public let sectionNameKeyPath: String?

	private(set) public weak var context: NSManagedObjectContext!

	internal let sections: Sections
	internal var prefetcher: ObjectCollectionPrefetcher<E>?

	private let predicate: NSPredicate

	fileprivate let objectComparer: ObjectComparer<E>
	fileprivate let sectionComparer: SectionComparer<E>

	private let sortKeys: [String]
	private let inSectionSortKeys: ArraySlice<String>
	private let sortOrderAffectingRelationships: [String]

	/// Unordered snapshot references, amortized O(1) lookup.
	fileprivate var objectCache: [ObjectReference<E>: ObjectSnapshot] = Dictionary()

	private var temporaryObjects = [ObjectIdentifier: ObjectReference<E>]()
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

		predicate = fetchRequest.predicate ?? NSPredicate(value: true)
		sortKeys = fetchRequest.sortDescriptors!.map { $0.key! }
		sortOrderAffectingRelationships = sortKeys
			.flatMap { key in
				let components = key.components(separatedBy: ".")
				return components.count >= 2 ? components[0] : nil
			}
			.uniquing()

		if sectionNameKeyPath != nil {
			precondition(fetchRequest.sortDescriptors!.count >= 2,
			             "Unsufficient number of sort descriptors.")

			self.objectComparer = ObjectComparer<E>(Array(fetchRequest.sortDescriptors!.dropFirst()))
			self.sectionComparer = SectionComparer(ascending: fetchRequest.sortDescriptors!.first!.ascending)
			self.inSectionSortKeys = sortKeys.dropFirst()
		} else {
			self.objectComparer = ObjectComparer<E>(fetchRequest.sortDescriptors ?? [])
			self.sectionComparer = SectionComparer(ascending: true)
			self.inSectionSortKeys = sortKeys[0 ..< sortKeys.endIndex]
		}

		sections = Tree(comparer: sectionComparer)

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

		objectComparer.collection = self
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

		func completion(_ results: [NSDictionary]) {
			// Search inserted objects in the context.
			let inMemoryResults = context.insertedObjects
				.flatMap { object -> E? in
					return qualifyingObject(object)
				}

			prefetcher?.reset()
			sectionize(using: results, inMemoryResults: inMemoryResults)
			prefetcher?.acknowledgeFetchCompletion(results.count)
			eventObserver.send(value: .reloaded)

			hasFetched = true
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
		sections.removeAll()
		var inMemoryChangedObjects = [SectionKey: Box<Set<ObjectReference<E>>>]()

		func markAsChanged(object registeredObject: E) {
			let id = ObjectReference<E>(registeredObject)
			updateCache(for: registeredObject, with: registeredObject)

			if let sectionNameKeyPath = sectionNameKeyPath {
				let sectionName = converting(sectionName: registeredObject.value(forKeyPath: sectionNameKeyPath) as! NSObject?)
				inMemoryChangedObjects.insert(id, intoSetOf: SectionKey(sectionName))
			} else {
				inMemoryChangedObjects.insert(id, intoSetOf: SectionKey(nil))
			}
		}

		if !resultDictionaries.isEmpty {
			var ranges: [(range: CountableRange<Int>, name: String?)] = []

			// Objects are sorted wrt sections already.
			for position in resultDictionaries.indices {
				if let sectionNameKeyPath = sectionNameKeyPath {
					let sectionName = converting(sectionName: resultDictionaries[position].object(forKey: sectionNameKeyPath))

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

			for (range, name) in ranges {
				let nodes = Tree<ObjectNode<E>, (), ObjectComparer<E>>(comparer: objectComparer)

				for position in range {
					let objectId = resultDictionaries[position]["objectID"] as! NSManagedObjectID

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
					if let registeredObject = context.registeredObject(for: objectId) as? E {
						guard predicate.evaluate(with: registeredObject) && !registeredObject.isDeleted else {
							continue
						}

						let changedValues = registeredObject.changedValues()
						let sortOrderIsAffected = sortOrderAffectingRelationships.contains { key in
							return changedValues[key] != nil
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

					let object = context.object(with: objectId) as! E

					if hasUpdatedRelationships {
						markAsChanged(object: object)
						continue
					}

					/// Use the results in the dictionary to update the cache.
					let snapshot = updateCache(for: object, with: resultDictionaries[position])
					let node = ObjectNode(reference: ObjectReference<E>(object), snapshot: snapshot)
					nodes.insert(node)
				}

				sections.insert(nodes, forKey: name)
			}
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

		for section in sections {
			section.value.updateCache()
		}

		sections.updateCache()
	}

	private func registerTemporaryObject(_ object: E) {
		temporaryObjects[ObjectIdentifier(object)] = ObjectReference<E>(object)

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

		if let insertedObjects = userInfo[NSInsertedObjectsKey] as? NSSet {
			var modifiedSections = Set<Tree<ObjectNode<E>, (), ObjectComparer<E>>>()

			for object in insertedObjects {
				guard type(of: object) is E.Type else {
					continue
				}

				let object = object as! E
				if let oldReference = temporaryObjects[ObjectIdentifier(object)] {
					if !object.objectID.isTemporaryID {
						/// If the object ID is no longer temporary, reinsert the object.
						let sectionIndex = sections.index(of: sectionName(of: object)!)!
						let section = sections[sectionIndex].value

						let oldSnapshot = clearCache(for: oldReference)
						let oldNode = ObjectNode(reference: oldReference, snapshot: oldSnapshot)
						section.remove(oldNode)

						let snapshot = updateCache(for: object, with: object)
						let newNode = ObjectNode(reference: ObjectReference<E>(object), snapshot: snapshot)
						section.insert(newNode)

						modifiedSections.insert(section)
					} else {
						fatalError("ObjectCollection does not implement any workaround to the temporary ID issue with parent-child context relationships. Please use `NSManagedObjectContext.obtainPermanentIDsForObjects(_:)` before saving your objects in a child context.")
					}
				}
			}

			for section in modifiedSections {
				section.updateCache()
			}
		}

		temporaryObjects = [:]
		isAwaitingContextSave = false
	}

	@discardableResult
	private func updateCache(for object: E, with values: NSObject) -> ObjectSnapshot {
		let reference = ObjectReference<E>(object)
		return updateCache(for: reference, with: values)
	}

	@discardableResult
	private func updateCache(for reference: ObjectReference<E>, with values: NSObject) -> ObjectSnapshot {
		let snapshot = ObjectSnapshot(sortKeys.map { key in
			return (values.value(forKeyPath: key) as AnyObject?) ?? NSNull()
		})

		if nil == objectCache.updateValue(snapshot, forKey: reference) {
			reference.retain()
		}

		return snapshot
	}

	@discardableResult
	private func clearCache(for object: E) -> ObjectSnapshot {
		return clearCache(for: ObjectReference<E>(object))
	}

	@discardableResult
	private func clearCache(for reference: ObjectReference<E>) -> ObjectSnapshot {
		reference.release()

		return objectCache.removeValue(forKey: reference)!
	}

	private func releaseCache() {
		let cache = objectCache
		objectCache = [:]

		for id in cache.keys {
			id.release()
		}
	}

	private func converting(sectionName: Any?) -> String? {
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
	private func qualifyingObject(_ object: Any) -> E? {
		if type(of: object) is E.Type {
			if predicate.evaluate(with: object) {
				return (object as! E)
			}
		}
		return nil
	}

	private func sortOrderIsAffected(by object: E, comparingWith snapshot: ObjectSnapshot) -> Bool {
		for i in inSectionSortKeys.indices {
			let value = object.value(forKeyPath: inSectionSortKeys[i]) as AnyObject
			if !value.isEqual(snapshot.wrapped[i]) {
				return true
			}
		}

		return false
	}

	private func processDeletedObjects(_ set: NSSet,
	                                   deleted deletedIds: inout [Box<Set<ObjectReference<E>>>],
	                                   cacheClearing cacheClearingIds: inout [ObjectReference<E>]) {
		for object in set {
			guard type(of: object) is E.Type else {
				continue
			}

			let object = object as! E
			let reference = ObjectReference<E>(object)

			if let snapshot = objectCache[reference] {
				let sectionName: String?

				if nil != sectionNameKeyPath {
					sectionName = converting(sectionName: snapshot.wrapped[0])
				} else {
					sectionName = nil
				}

				if let index = sections.index(of: sectionName) {
					deletedIds.insert(reference, intoSetAt: index)
					cacheClearingIds.append(reference)
				}
			}
		}
	}

	private func processUpdatedObjects(_ set: NSSet,
	                                   inserted insertedIds: inout [SectionKey: Box<Set<ObjectReference<E>>>],
	                                   updated updatedIds: inout [Box<Set<ObjectReference<E>>>],
	                                   sortOrderAffecting sortOrderAffectingIndexPaths: inout [Box<Set<Int>>],
	                                   sectionChanged sectionChangedIndexPaths: inout [Box<Set<Int>>],
	                                   deleted deletedIds: inout [Box<Set<ObjectReference<E>>>],
	                                   cacheClearing cacheClearingIds: inout [ObjectReference<E>]) {
		for object in set {
			let type = type(of: object)

			if type is E.Type {
				let object = object as! E
				let reference = ObjectReference<E>(object)
				let snapshot = objectCache[reference]

				if !predicate.evaluate(with: object) {
					guard let snapshot = snapshot else {
						continue
					}

					/// The object no longer qualifies. Delete it from the ObjectCollection.
					let sectionName: String?

					if nil != sectionNameKeyPath {
						sectionName = converting(sectionName: snapshot.wrapped[0])
					} else {
						sectionName = nil
					}

					if let index = sections.index(of: sectionName) {
						/// Use binary search, but compare against the previous values dictionary.
						deletedIds.insert(reference, intoSetAt: index)
						cacheClearingIds.append(reference)
						continue
					}
				} else if let snapshot = snapshot {
					let node = ObjectNode(reference: reference, snapshot: snapshot)

					/// The object still qualifies. Does it have any change affecting the sort order?
					let currentSectionName: String?

					if nil != sectionNameKeyPath {
						let previousSectionName = converting(sectionName: snapshot.wrapped[0])
						currentSectionName = sectionName(of: object)

						guard previousSectionName == currentSectionName else {
							guard let previousSectionIndex = sections.index(of: currentSectionName) else {
								preconditionFailure("current section name is supposed to exist, but not found.")
							}

							guard let objectIndex = sections[previousSectionIndex].value.index(of: node) else {
								preconditionFailure("An object should be in section \(previousSectionIndex), but it cannot be found. (ID: \(object.objectID.uriRepresentation()))")
							}

							sectionChangedIndexPaths.insert(objectIndex, intoSetAt: previousSectionIndex)
							updateCache(for: reference, with: object)
							continue
						}
					} else {
						currentSectionName = nil
					}

					guard let currentSectionIndex = sections.index(of: currentSectionName) else {
						preconditionFailure("current section name is supposed to exist, but not found.")
					}

					guard !sortOrderIsAffected(by: object, comparingWith: snapshot) else {
						guard let objectIndex = sections[currentSectionIndex].value.index(of: node) else {
							preconditionFailure("An object should be in section \(currentSectionIndex), but it cannot be found. (ID: \(object.objectID.uriRepresentation()))")
						}

						sortOrderAffectingIndexPaths.insert(objectIndex, intoSetAt: currentSectionIndex)
						updateCache(for: reference, with: object)
						continue
					}

					if !shouldExcludeUpdatedRows {
						updatedIds.insert(reference, intoSetAt: currentSectionIndex)
					}
				} else {
					let currentSectionName = sectionName(of: object)
					insertedIds.insert(reference, intoSetOf: SectionKey(currentSectionName))
					updateCache(for: reference, with: object)
					continue
				}
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
			releaseCache()
			sections.removeAll()
			return
		}

		/// Reference sections by name, since these objects may lead to creating a new section.
		var insertedIds = [SectionKey: Box<Set<ObjectReference<E>>>]()

		/// Referencing sections by the index in snapshot.
		var sectionChangedIndexPaths = sections.indices.map { _ in Box(Set<Int>()) }
		var deletedIds = sections.indices.map { _ in Box(Set<ObjectReference<E>>()) }
		var updatedIds = sections.indices.map { _ in Box(Set<ObjectReference<E>>()) }
		var sortOrderAffectingIndexPaths = sections.indices.map { _ in Box(Set<Int>()) }
		var cacheClearingIds = [ObjectReference<E>]()

		if let _insertedObjects = userInfo[NSInsertedObjectsKey] as? NSSet {
			let previouslyInsertedObjects = NSMutableSet()

			for object in _insertedObjects {
				if let object = qualifyingObject(object) {
					let reference = ObjectReference<E>(object)

					if nil != objectCache.index(forKey: reference) {
						previouslyInsertedObjects.add(object)
					} else {
						let name = sectionName(of: object)
						insertedIds.insert(reference, intoSetOf: SectionKey(name))
						updateCache(for: object, with: object)

						if object.objectID.isTemporaryID {
							registerTemporaryObject(object)
						}
					}
				}
			}

			if previouslyInsertedObjects.count > 0 {
				processUpdatedObjects(previouslyInsertedObjects,
				                      inserted: &insertedIds,
				                      updated: &updatedIds,
				                      sortOrderAffecting: &sortOrderAffectingIndexPaths,
				                      sectionChanged: &sectionChangedIndexPaths,
				                      deleted: &deletedIds,
				                      cacheClearing: &cacheClearingIds)
			}
		}

		if let deletedObjects = userInfo[NSDeletedObjectsKey] as? NSSet {
			processDeletedObjects(deletedObjects,
			                      deleted: &deletedIds,
			                      cacheClearing: &cacheClearingIds)
		}

		if let invalidatedObjects = userInfo[NSInvalidatedObjectsKey] as? NSSet {
			processDeletedObjects(invalidatedObjects,
			                      deleted: &deletedIds,
			                      cacheClearing: &cacheClearingIds)
		}

		if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? NSSet {
			processUpdatedObjects(updatedObjects,
			                      inserted: &insertedIds,
			                      updated: &updatedIds,
			                      sortOrderAffecting: &sortOrderAffectingIndexPaths,
			                      sectionChanged: &sectionChangedIndexPaths,
			                      deleted: &deletedIds,
			                      cacheClearing: &cacheClearingIds)
		}

		if let refreshedObjects = userInfo[NSRefreshedObjectsKey] as? NSSet {
			processUpdatedObjects(refreshedObjects,
			                      inserted: &insertedIds,
			                      updated: &updatedIds,
			                      sortOrderAffecting: &sortOrderAffectingIndexPaths,
			                      sectionChanged: &sectionChangedIndexPaths,
			                      deleted: &deletedIds,
			                      cacheClearing: &cacheClearingIds)
		}

		for id in cacheClearingIds {
			clearCache(for: id.wrapped)
		}

		let changes = mergeChanges(inserted: insertedIds,
		                           deleted: deletedIds,
		                           updated: updatedIds,
		                           sortOrderAffecting: sortOrderAffectingIndexPaths,
		                           sectionChanged: sectionChangedIndexPaths)

		eventObserver.send(value: .updated(changes))
	}

	/// Merge the specific changes and compute the changes descriptor.
	///
	/// - parameters:
	///   - insertedObjects: Inserted object IDs for the affected sections.
	///   - deletedObjects: Object IDs of deleted objects in every section.
	///   - updatedObjects: IDs of updated objects in every section.
	///   - sortOrderAffectingObjects: Indices of sort order affecting objects
	///                                in every section.
	///   - sectionChangedObjects: Indices of moving-across-sections objects in
	///                            every section.
	///
	/// - returns:
	///   The changes descriptor.
	private func mergeChanges(
		inserted insertedObjects: [SectionKey: Box<Set<ObjectReference<E>>>],
		deleted deletedObjects: [Box<Set<ObjectReference<E>>>],
		updated updatedObjects: [Box<Set<ObjectReference<E>>>],
		sortOrderAffecting sortOrderAffectingObjects: [Box<Set<Int>>],
		sectionChanged sectionChangedObjects: [Box<Set<Int>>]
	) -> SectionedCollectionChanges {
		/// Process deletions first, and buffer moves and insertions.
		var oldSectionNames = [SectionKey: Int]()
		for (i, section) in sections.enumerated() {
			oldSectionNames[SectionKey(section.key)] = i
		}

		let insertedObjectsCount = insertedObjects.reduce(0) { $0 + $1.1.value.count }
		let deletedObjectsCount = deletedObjects.reduce(0) { $0 + $1.value.count }
		let sectionChangedObjectsCount = sectionChangedObjects.reduce(0) { $0 + $1.value.count }
		let updatedObjectsCount = updatedObjects.reduce(0) { $0 + $1.value.count }
		let sortOrderAffectingObjectsCount = sortOrderAffectingObjects.reduce(0) { $0 + $1.value.count }

		var inboundObjects = [SectionKey: Box<Set<ObjectReference<E>>>]()
		var inPlaceMovingObjects = sections.indices.map { _ in Box(Set<ObjectReference<E>>()) }
		var deletedObjects = deletedObjects

		var originOfSectionChangedObjects: [ObjectReference<E>: IndexPath] = Dictionary(minimumCapacity: sectionChangedObjectsCount)
		var originOfMovedObjects: [ObjectReference<E>: IndexPath] = Dictionary(minimumCapacity: sortOrderAffectingObjectsCount)

		var indexPathsOfInsertedRows = [IndexPath]()
		var indexPathsOfUpdatedRows = [IndexPath]()
		var indexPathsOfMovedRows = [(from: IndexPath, to: IndexPath)]()
		var indexPathsOfDeletedRows = [IndexPath]()

		var indiceOfDeletedSections = IndexSet()
		var indiceOfInsertedSections = IndexSet()

		indexPathsOfInsertedRows.reserveCapacity(insertedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(sectionChangedObjectsCount + sortOrderAffectingObjectsCount)

		// Flatten objects that moved across sections into IndexPaths.
		for (previousSectionIndex, indices) in sectionChangedObjects.enumerated() {
			let section = sections[previousSectionIndex].value

			for previousObjectIndex in indices.value {
				let node = section[previousObjectIndex].key
				deletedObjects.insert(node.reference, intoSetAt: previousSectionIndex)

				let indexPath = IndexPath(row: previousObjectIndex, section: previousSectionIndex)
				originOfSectionChangedObjects[node.reference] = indexPath

				let newSectionName = sectionName(of: node.reference.wrapped)
				inboundObjects.insert(node.reference, intoSetOf: SectionKey(newSectionName))
			}
		}

		// Flatten objects that moved within sections into IndexPaths.
		for (sectionIndex, indices) in sortOrderAffectingObjects.enumerated() {
			let section = sections[sectionIndex].value

			for previousObjectIndex in indices.value {
				let node = section[previousObjectIndex].key

				deletedObjects.insert(node.reference, intoSetAt: sectionIndex)

				let indexPath = IndexPath(row: previousObjectIndex, section: sectionIndex)
				originOfMovedObjects[node.reference] = indexPath

				inPlaceMovingObjects.insert(node.reference, intoSetAt: sectionIndex)
			}
		}

		/// Notify the prefetcher for changes.
		prefetcher?.acknowledgeChanges(inserted: insertedObjects, deleted: deletedObjects)

		// Delete marked objects from the sections.
		for sectionIndex in sections.indices.reversed() {
			let section = sections[sectionIndex].value
			let deletedObjects = deletedObjects[sectionIndex]
			var indices = [Int]()

			for objectIndex in (0 ..< section.count).reversed() {
				if deletedObjects.value.contains(section[objectIndex].key.reference) {
					section.remove(at: objectIndex)
					indices.append(objectIndex)
				}
			}

			if section.count == 0 && inPlaceMovingObjects[sectionIndex].value.count == 0 {
				sections.remove(at: sectionIndex)
				indiceOfDeletedSections.insert(sectionIndex)
			} else {
				for index in indices {
					indexPathsOfDeletedRows.append(IndexPath(row: index, section: sectionIndex))
				}
			}
		}

		/// MARK: Handle insertions.

		func insert(_ references: Box<Set<ObjectReference<E>>>, intoSectionFor name: String?) {
			let section = sections.index(of: name).map { sections[$0].value } ?? {
				let node = Tree<ObjectNode<E>, (), ObjectComparer<E>>(comparer: objectComparer)
				self.sections.insert(node, forKey: name)
				return node
			}()

			for reference in references.value {
				let node = ObjectNode(reference: reference, snapshot: objectCache[reference]!)
				section.insert(node)
			}
		}

		for (sectionName, objects) in insertedObjects {
			insert(objects, intoSectionFor: sectionName.value)
		}

		for (sectionName, objects) in inboundObjects {
			insert(objects, intoSectionFor: sectionName.value)
		}

		/// MARK: Index generating full pass.

		var sectionIndex = 0
		sections.cacheUpdatingForEach { section in
			defer { sectionIndex += 1 }

			let previousSectionIndex = oldSectionNames[SectionKey(section.key)]

			if let previousSectionIndex = previousSectionIndex {
				for reference in inPlaceMovingObjects[previousSectionIndex].value {
					let node = ObjectNode(reference: reference, snapshot: objectCache[reference]!)
					section.value.insert(node)
				}
			} else {
				indiceOfInsertedSections.insert(sectionIndex)
			}

			let insertedObjects = insertedObjects[SectionKey(section.key)] ?? Box([])
			let inboundObjects = inboundObjects[SectionKey(section.key)] ?? Box([])

			var offset = 0
			section.value.cacheUpdatingForEach { node in
				let node = node.key
				defer { offset += 1 }

				// Emit index paths for updated rows, if enabled.
				if !shouldExcludeUpdatedRows {
					if let oldSectionIndex = previousSectionIndex,
					   updatedObjects[oldSectionIndex].value.contains(node.reference) {
						let indexPath = IndexPath(row: offset, section: sectionIndex)
						indexPathsOfUpdatedRows.append(indexPath)
						return
					}
				}

				// Insertions to existing sections.
				if previousSectionIndex != nil && insertedObjects.value.contains(node.reference) {
					let indexPath = IndexPath(row: offset, section: sectionIndex)
					indexPathsOfInsertedRows.append(indexPath)
					return
				}

				// Moved objects within the same section.
				if let indexPath = originOfMovedObjects[node.reference] {
					let from = indexPath
					let to = IndexPath(row: offset, section: sectionIndex)
					indexPathsOfMovedRows.append((from, to))
					return
				}

				// Moved objects across sections.
				if inboundObjects.value.contains(node.reference) {
					let origin = originOfSectionChangedObjects[node.reference]!

					if indiceOfDeletedSections.contains(origin.section) {
						/// The originated section no longer exists, treat it as an inserted row.
						let indexPath = IndexPath(row: offset, section: sectionIndex)
						indexPathsOfInsertedRows.append(indexPath)
						return
					}

					if indiceOfInsertedSections.contains(sectionIndex) {
						/// The target section is newly created.
						return
					}

					let to = IndexPath(row: offset, section: sectionIndex)
					indexPathsOfMovedRows.append((origin, to))
					return
				}
			}
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
		releaseCache()
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
		return IndexPath(row: sections[cached: start].value.startIndex, section: start)
	}

	public var endIndex: IndexPath {
		return IndexPath(row: 0, section: sections.endIndex)
	}

	public var count: Int {
		return sections.reduce(0) { $0 + $1.value.count }
	}

	public func index(before i: IndexPath) -> IndexPath {
		let section = sections[cached: i.section].value

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
		return IndexPath(row: sections[cached: next].value.startIndex, section: next)
	}

	public func index(after i: IndexPath) -> IndexPath {
		let section = sections[cached: i.section].value

		if i.row + 1 < section.endIndex {
			return IndexPath(row: i.row + 1, section: i.section)
		} else {
			if i.section + 1 == section.endIndex {
				return endIndex
			} else {
				return IndexPath(row: 0, section: i.section + 1)
			}
		}
	}

	public func distance(from start: IndexPath, to end: IndexPath) -> Int {
		let sectionDiff = end.section - start.section

		if sectionDiff == 0 {
			return end.row - start.row
		}

		if sectionDiff > 0 {
			let loopStart = sections.index(after: start.section)
			var count = (sections[cached: start.section].value.endIndex - start.row) + end.row

			for i in loopStart ..< end.section {
				count += sections[cached: i].value.count
			}

			return count
		} else {
			let loopStart = sections.index(after: end.section)
			var count = (start.row - sections[cached: start.section].value.startIndex + 1) + (sections[cached: end.section].value.endIndex - end.row)

			for i in loopStart ..< start.section {
				count += sections[cached: i].value.count
			}

			return count
		}
	}

	public subscript(row row: Int, section section: Int) -> E {
		prefetcher?.acknowledgeNextAccess(at: (row: row, section: section))
		let node = sections[cached: section].value[cached: row].key
		return node.reference.wrapped
	}

	public subscript(position: IndexPath) -> E {
		return self[row: position.row, section: position.section]
	}

	public subscript(subRange: Range<IndexPath>) -> RandomAccessSlice<ObjectCollection<E>> {
		return RandomAccessSlice(base: self, bounds: subRange)
	}

	public func sectionName(for section: Int) -> String? {
		return sections[cached: section].key
	}

	public func rowCount(for section: Int) -> Int {
		return sections[cached: section].value.count
	}

	public func indexPath(of element: E) -> IndexPath? {
		let reference = ObjectReference<E>(element)
		guard let snapshot = objectCache[reference] else {
			return nil
		}

		let node = ObjectNode(reference: reference, snapshot: snapshot)
		let name = sectionName(of: element)

		if let sectionIndex = sections.index(of: name) {
			if let objectIndex = sections[cached: sectionIndex].value.index(of: node) {
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

internal struct ObjectReference<E: NSManagedObject>: Hashable {
	unowned(unsafe) let wrapped: E
	let hashValue: Int

	init(_ object: E) {
		wrapped = object
		hashValue = object.hash
	}

	func retain() {
		_ = Unmanaged.passRetained(wrapped)
	}

	func release() {
		Unmanaged.passUnretained(wrapped).release()
	}

	static func ==(left: ObjectReference<E>, right: ObjectReference<E>) -> Bool {
		// Objects are uniqued.
		return left.wrapped === right.wrapped
	}
}

internal struct ObjectSnapshot {
	let wrapped: [AnyObject]

	init(_ dictionary: [AnyObject]) {
		wrapped = dictionary
	}
}

internal struct ObjectNode<E: NSManagedObject> {
	let reference: ObjectReference<E>
	let snapshot: ObjectSnapshot

	init(reference: ObjectReference<E>, snapshot: ObjectSnapshot) {
		self.reference = reference
		self.snapshot = snapshot
	}
}

extension ObjectNode: CustomDebugStringConvertible {
	var debugDescription: String {
		return "ObjNode \(ObjectIdentifier(reference.wrapped))"
	}
}

@objc protocol NSObjectComparing: class {
	func compare(_ other: AnyObject?) -> ComparisonResult
}

internal final class SectionComparer<E: NSManagedObject>: TreeComparer {
	let ascending: Bool

	init(ascending: Bool) {
		self.ascending = ascending
	}

	func compare(_ left: String?, to right: String?) -> ComparisonResult {
		let order: ComparisonResult

		if let left = left, let right = right {
			order = left.compare(right)
		} else {
			order = left == nil ? (right == nil ? .orderedSame : .orderedAscending) : .orderedDescending
		}

		switch order {
		case .orderedSame:
			return .orderedSame

		case .orderedAscending:
			return ascending ? .orderedAscending : .orderedDescending

		case .orderedDescending:
			return ascending ? .orderedDescending : .orderedAscending
		}
	}

	func testEquality(_ first: String?, _ second: String?) -> Bool {
		return first == second
	}
}

internal final class ObjectComparer<E: NSManagedObject>: TreeComparer {
	typealias Element = ObjectNode<E>

	let isAscending: [Bool]
	weak var collection: ObjectCollection<E>!

	init(_ sortDescriptors: [NSSortDescriptor]) {
		self.isAscending = sortDescriptors.map { $0.ascending }
	}

	func compare(_ left: ObjectSnapshot, to right: ObjectSnapshot) -> ComparisonResult {
		for (i, isAscending) in isAscending.enumerated() {
			let order = left.wrapped[i].compare(right.wrapped[i])
			if order != .orderedSame {
				return isAscending ? order : (order == .orderedAscending ? .orderedDescending : .orderedAscending)
			}
		}

		return .orderedSame
	}

	func compare(_ id: ObjectReference<E>, to anotherId: ObjectReference<E>) -> ComparisonResult {
		let left = collection.objectCache[id]!
		let right = collection.objectCache[anotherId]!

		return compare(left, to: right)
	}

	func compare(_ node: ObjectNode<E>, to anotherNode: ObjectNode<E>) -> ComparisonResult {
		let left = UInt(bitPattern: ObjectIdentifier(node.reference.wrapped))
		let right = UInt(bitPattern: ObjectIdentifier(anotherNode.reference.wrapped))

		if left == right {
			return .orderedSame
		}

		let order = compare(node.snapshot, to: anotherNode.snapshot)

		if order != .orderedSame {
			return order
		}

		// Assumption: left != right
		return left < right ? .orderedAscending : .orderedDescending
	}

	func testEquality(_ first: ObjectNode<E>, _ second: ObjectNode<E>) -> Bool {
		return first.reference == second.reference
	}
}
