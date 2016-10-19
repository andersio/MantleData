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
	private let lifetimeToken = Lifetime.Token()

	// Lifetime.
	public let lifetime: Lifetime

	// Configurations.
	public let ignoresUpdatedRows: Bool
	public let refetchesAfterInvalidation: Bool
	public let sectionNameKeyPath: String?

	// Context.
	private(set) public weak var context: NSManagedObjectContext!

	// Fetch parameters.
	private let fetchRequest: NSFetchRequest<NSDictionary>
	private let entity: NSEntityDescription
	private let predicate: NSPredicate

	fileprivate let sortsAscendingSectionName: Bool
	fileprivate let objectComparer: Comparer<E>
	private let sortKeys: [String]
	private let _sortKeys: [NSCopying]
	private let sortKeyComponents: [(String, [String])]
	private let sortOrderAffectingRelationships: [String]
	private let sortKeysInSections: [String]
	internal let prefetchingRelationships: [String]

	// Mutable states.
	internal var sections: [ObjectCollectionSection<E>] = []
	internal var prefetcher: ObjectCollectionPrefetcher<E>?
	fileprivate var objectCache: [ObjectReference<E>: ObjectSnapshot] = [:]
	private var temporaryObjects = [ObjectIdentifier: ObjectReference<E>]()
	private var isAwaitingContextSave = false
	public private(set) var hasFetched: Bool = false

	// Events.
	public let events: Signal<SectionedCollectionEvent, NoError>
	private var eventObserver: Observer<SectionedCollectionEvent, NoError>


	public init(for fetchRequest: NSFetchRequest<E>,
							in context: NSManagedObjectContext,
							prefetchingPolicy: ObjectCollectionPrefetchingPolicy,
							sectionNameKeyPath: String? = nil,
							prefetchingRelationships: [String] = [],
							ignoresUpdatedRows: Bool = true,
							refetchesAfterInvalidation: Bool = true) {
		(events, eventObserver) = Signal.pipe()
		lifetime = Lifetime(lifetimeToken)

		self.context = context
		self.entity = fetchRequest.entity!
		self.ignoresUpdatedRows = ignoresUpdatedRows
		self.refetchesAfterInvalidation = refetchesAfterInvalidation
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

			self.sortsAscendingSectionName = fetchRequest.sortDescriptors!.first!.ascending
			self.objectComparer = Comparer<E>(Array(fetchRequest.sortDescriptors!.dropFirst()),
			                                  groupsBySection: true)
		} else {
			self.sortsAscendingSectionName = true
			self.objectComparer = Comparer<E>(fetchRequest.sortDescriptors!,
			                                  groupsBySection: false)
		}

		predicate = fetchRequest.predicate ?? NSPredicate(value: true)

		sortKeys = fetchRequest.sortDescriptors!.map { $0.key! }
		_sortKeys = sortKeys as [NSCopying]
		sortKeysInSections = Array(sortKeys.dropFirst())
		sortKeyComponents = sortKeys.map { ($0, $0.components(separatedBy: ".")) }
		sortOrderAffectingRelationships = sortKeyComponents.flatMap { $0.1.count > 1 ? $0.1[0] : nil }.uniquing()
		self.prefetchingRelationships = prefetchingRelationships

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
			.observeValues(self.process(objectsDidChangeNotification:))

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
	/// - parameters:
	///   - async: Whether the fetch should be run asynchronously.
	public func fetch(async: Bool = false) throws {
		func completion(_ results: [NSDictionary]) {
			_reset()

			var inMemoryChangedObjects = [SectionKey: Box<Set<ObjectReference<E>>>]()

			func markAsChanged(object registeredObject: E) {
				let reference = ObjectReference<E>(registeredObject)
				updateCache(for: reference, with: registeredObject)

				if let sectionNameKeyPath = sectionNameKeyPath {
					let sectionName = converting(sectionName: registeredObject.value(forKeyPath: sectionNameKeyPath) as! NSObject?)
					inMemoryChangedObjects.insert(reference, intoSetOf: SectionKey(sectionName))
				} else {
					inMemoryChangedObjects.insert(reference, intoSetOf: SectionKey(nil))
				}
			}

			if !results.isEmpty {
				var ranges: [(range: CountableRange<Int>, name: String?)] = []

				// Objects are sorted wrt sections already.
				for position in results.indices {
					if let sectionNameKeyPath = sectionNameKeyPath {
						let sectionName = converting(sectionName: results[position].object(forKey: sectionNameKeyPath))

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

				for (range, name) in ranges {
					var references = [ObjectReference<E>]()
					references.reserveCapacity(range.count)

					for position in range {
						let objectId = results[position]["objectID"] as! NSManagedObjectID
						let object = context.object(with: objectId) as! E

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
						if object.hasPersistentChangedValues {
							let changedKeys = object.changedValues().keys
							let sortOrderIsAffected = sortKeyComponents.contains { changedKeys.contains($0.1[0]) }

							guard predicate.evaluate(with: object) && !object.isDeleted else {
								continue
							}

							if sortOrderIsAffected {
								markAsChanged(object: object)
								continue
							}
						}

						// If the sort order affecting relationships of the object are
						// registered with the context and has in-memory changes, the object
						// is faulted in and the object cache is updated subsequently. But the
						// insertion is deferred.
						let hasUpdatedRelationships = sortOrderAffectingRelationships.contains { key in
							if let relationshipID = results[position][key] as? NSManagedObjectID,
							 let relatedObject = context.registeredObject(for: relationshipID),
							 relatedObject.isUpdated {
								return true
							}
							return false
						}

						if hasUpdatedRelationships {
							markAsChanged(object: object)
							continue
						}

						/// Use the results in the dictionary to update the cache.
						let reference = ObjectReference<E>(object)
						updateCache(for: reference, with: results[position])
						references.append(reference)
					}

					let section = ObjectCollectionSection(name: name, array: references)
					sections.append(section)
				}
			}

			// Search inserted objects in the context.
			context.insertedObjects
				.flatMap(self.qualifyingObject)
				.forEach { object in
					markAsChanged(object: object)
					registerTemporaryObject(object)
				}

			if !inMemoryChangedObjects.isEmpty {
				_ = mergeChanges(inserted: inMemoryChangedObjects,
				                 deleted: [],
				                 updated: [],
				                 sortOrderAffecting: [],
				                 sectionChanged: [])
			}

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
				completion(try context.fetch(fetchRequest))
			}
		} catch let error {
			fatalError("\(error)")
		}
	}

	public func reset() {
		_reset()
		eventObserver.send(value: .reloaded)
	}

	private func _reset() {
		prefetcher?.reset()

		sections = []

		if hasFetched {
			isAwaitingContextSave = false
			temporaryObjects = [:]
			releaseCache()
		}
	}

	private func registerTemporaryObject(_ object: E) {
		temporaryObjects[ObjectIdentifier(object)] = ObjectReference<E>(object)

		if !isAwaitingContextSave {
			NotificationCenter.default
				.reactive
				.notifications(forName: NSNotification.Name.NSManagedObjectContextDidSave, object: context)
				.take(first: 1)
				.observeValues(handle(contextDidSaveNotification:))

			isAwaitingContextSave = true
		}
	}

	@objc private func handle(contextDidSaveNotification notification: Notification) {
		guard isAwaitingContextSave, let userInfo = (notification as NSNotification).userInfo else {
			return
		}

		if let insertedObjects = userInfo[NSInsertedObjectsKey] as? NSSet {
			for object in insertedObjects {
				guard type(of: object) is E.Type else {
					continue
				}

				let object = object as! E
				if let temporaryReference = temporaryObjects[ObjectIdentifier(object)] {
					if !object.objectID.isTemporaryID {
						/// If the object ID is no longer temporary, find the position of the object.
						/// Then update the object and the cache with the permanent ID.

						let sectionIndex = sections.index(of: sectionName(of: object)!, ascending: sortsAscendingSectionName)!
						let objectIndex = sections[sectionIndex].storage.index(of: temporaryReference, with: objectComparer)!

						sections[sectionIndex].storage[objectIndex] = ObjectReference<E>(object)
						clearCache(for: temporaryReference)
						updateCache(for: object, with: object)
					} else {
						fatalError("ObjectCollection does not implement any workaround to the temporary ID issue with parent-child context relationships. Please use `NSManagedObjectContext.obtainPermanentIDsForObjects(_:)` before saving your objects in a child context.")
					}
				}
			}
		}

		temporaryObjects = [:]
		isAwaitingContextSave = false
	}

	private func updateCache(for object: E, with values: NSObject) {
		updateCache(for: ObjectReference(object), with: values)
	}

	private func clearCache(for object: E) {
		clearCache(for: ObjectReference(object))
	}

	private func updateCache(for reference: ObjectReference<E>, with values: NSObject) {
		let snapshot = ObjectSnapshot(sortKeys.map { key in
			return (values.value(forKeyPath: key) as AnyObject?) ?? NSNull()
		})

		if nil == objectCache.updateValue(snapshot, forKey: reference) {
			reference.retain()
		}
	}

	private func clearCache(for reference: ObjectReference<E>) {
		if nil != objectCache.removeValue(forKey: reference) {
			reference.release()
		}
	}

	private func releaseCache() {
		let cache = objectCache
		objectCache = [:]

		for reference in cache.keys {
			reference.release()
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
		for (i, key) in sortKeysInSections.enumerated() {
			let value = object.value(forKeyPath: key) as AnyObject
			if !value.isEqual(snapshot.wrapped[1 + i]) {
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
			let id = ObjectReference<E>(object)

			if let snapshot = objectCache[id] {
				let sectionName: String?

				if nil != sectionNameKeyPath {
					sectionName = converting(sectionName: snapshot.wrapped[0])
				} else {
					sectionName = nil
				}

				if let index = sections.index(of: sectionName, ascending: sortsAscendingSectionName) {
					deletedIds.insert(id, intoSetAt: index)
					cacheClearingIds.append(id)
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
				let id = ObjectReference<E>(object)
				let snapshot = objectCache[id]

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

					if let index = sections.index(of: sectionName, ascending: sortsAscendingSectionName) {
						/// Use binary search, but compare against the previous values dictionary.
						deletedIds.insert(id, intoSetAt: index)
						cacheClearingIds.append(id)
						continue
					}
				} else if let snapshot = snapshot {
					/// The object still qualifies. Does it have any change affecting the sort order?
					let currentSectionName: String?

					if nil != sectionNameKeyPath {
						let previousSectionName = converting(sectionName: snapshot.wrapped[0])
						currentSectionName = sectionName(of: object)

						guard previousSectionName == currentSectionName else {
							guard let previousSectionIndex = sections.index(of: currentSectionName, ascending: sortsAscendingSectionName) else {
								preconditionFailure("current section name is supposed to exist, but not found.")
							}

							guard let objectIndex = sections[previousSectionIndex].storage.index(of: id, with: objectComparer) else {
								preconditionFailure("An object should be in section \(previousSectionIndex), but it cannot be found. (ID: \(object.objectID.uriRepresentation()))")
							}

							sectionChangedIndexPaths.insert(objectIndex, intoSetAt: previousSectionIndex)
							updateCache(for: id.wrapped, with: object)
							continue
						}
					} else {
						currentSectionName = nil
					}

					guard let currentSectionIndex = sections.index(of: currentSectionName, ascending: sortsAscendingSectionName) else {
						preconditionFailure("current section name is supposed to exist, but not found.")
					}

					guard !sortOrderIsAffected(by: object, comparingWith: snapshot) else {
						guard let objectIndex = sections[currentSectionIndex].storage.index(of: id, with: objectComparer) else {
							preconditionFailure("An object should be in section \(currentSectionIndex), but it cannot be found. (ID: \(object.objectID.uriRepresentation()))")
						}

						sortOrderAffectingIndexPaths.insert(objectIndex, intoSetAt: currentSectionIndex)
						updateCache(for: id.wrapped, with: object)
						continue
					}
					
					if !ignoresUpdatedRows {
						updatedIds.insert(id, intoSetAt: currentSectionIndex)
					}
				} else {
					let currentSectionName = sectionName(of: object)
					insertedIds.insert(id, intoSetOf: SectionKey(currentSectionName))
					updateCache(for: id.wrapped, with: object)
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
			if refetchesAfterInvalidation {
				try! fetch(async: true)
			} else {
				reset()
			}
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
					let id = ObjectReference<E>(object)

					if nil != objectCache.index(forKey: id) {
						previouslyInsertedObjects.add(object)
					} else {
						let name = sectionName(of: object)
						insertedIds.insert(id, intoSetOf: SectionKey(name))
						updateCache(for: id.wrapped, with: object)

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
		let previousSectionNames = sections.map { SectionKey($0.name) }

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
		for (prevS, indices) in sectionChangedObjects.enumerated() {
			for prevR in indices.value {
				let id = sections[prevS].storage[prevR]
				deletedObjects.insert(id, intoSetAt: prevS)

				let indexPath = IndexPath(row: prevR, section: prevS)
				originOfSectionChangedObjects[id] = indexPath

				let newSectionName = sectionName(of: id.wrapped)
				inboundObjects.insert(id, intoSetOf: SectionKey(newSectionName))
			}
		}

		// Flatten objects that moved within sections into IndexPaths.
		for (s, indices) in sortOrderAffectingObjects.enumerated() {
			for prevR in indices.value {
				let id = sections[s].storage[prevR]

				deletedObjects.insert(id, intoSetAt: s)

				let indexPath = IndexPath(row: prevR, section: s)
				originOfMovedObjects[id] = indexPath

				inPlaceMovingObjects.insert(id, intoSetAt: s)
			}
		}

		/// Notify the prefetcher for changes.
		prefetcher?.acknowledgeChanges(inserted: insertedObjects, deleted: deletedObjects)

		// Delete marked objects from the sections.
		for s in sections.indices.reversed() {
			let section = sections[s]
			let deletedObjects = deletedObjects[s]
			var indices = [Int]()

			var removal = section.storage.endIndex ..< section.storage.endIndex

			for r in section.storage.indices.reversed() {
				if deletedObjects.value.contains(section.storage[r]) {
					removal = r ..< removal.upperBound
				} else {
					section.storage.removeSubrange(removal)
					let index = section.storage.index(before: r)
					removal = r ..< r
				}
			}

			if !removal.isEmpty {
				section.storage.removeSubrange(removal)
			}

			if section.storage.count == 0 && inPlaceMovingObjects[s].value.count == 0 {
				sections.remove(at: s)
				indiceOfDeletedSections.insert(s)
			} else {
				let sortOrderAffecting = sortOrderAffectingObjects[s]
				let sectionChanged = sectionChangedObjects[s]

				for index in indices {
					if !sortOrderAffecting.value.contains(index) && !sectionChanged.value.contains(index) {
						indexPathsOfDeletedRows.append(IndexPath(row: index, section: s))
					}
				}
			}
		}

		/// MARK: Handle insertions.

		func insert(_ ids: Box<Set<ObjectReference<E>>>, intoSectionFor name: SectionKey) {
			let sectionIndex = sections.index(of: name.name, ascending: sortsAscendingSectionName) ?? {
				let section = ObjectCollectionSection<E>(name: name.name, array: [])
				return self.sections.insert(section, name: name.name, ascending: sortsAscendingSectionName)
			}()

			for id in ids.value {
				sections[sectionIndex].storage.insert(id, with: objectComparer)
			}
		}

		for (sectionName, objects) in insertedObjects {
			insert(objects, intoSectionFor: sectionName)
		}

		for (sectionName, objects) in inboundObjects {
			insert(objects, intoSectionFor: sectionName)
		}

		/// MARK: Index generating full pass.

		for (s, section) in sections.enumerated() {
			let prevS = previousSectionNames.index(of: section.name, ascending: sortsAscendingSectionName)

			let inboundObjects = inboundObjects[SectionKey(section.name)] ?? Box([])

			if let prevS = prevS {
				for id in inPlaceMovingObjects[prevS].value {
					section.storage.insert(id, with: objectComparer)
				}
			} else {
				indiceOfInsertedSections.insert(s)

				for object in inboundObjects.value {
					let origin = originOfMovedObjects[object]!
					indexPathsOfDeletedRows.append(origin)
				}
				continue
			}

			let insertedObjects = insertedObjects[SectionKey(section.name)] ?? Box([])

			for (r, reference) in section.storage.enumerated() {
				// Emit index paths for updated rows, if enabled.
				if !ignoresUpdatedRows {
					if let prevS = prevS, updatedObjects[prevS].value.contains(reference) {
						let indexPath = IndexPath(row: r, section: s)
						indexPathsOfUpdatedRows.append(indexPath)
						continue
					}
				}

				// Insertions to existing sections.
				if prevS != nil && insertedObjects.value.contains(reference) {
					let indexPath = IndexPath(row: r, section: s)
					indexPathsOfInsertedRows.append(indexPath)
					continue
				}

				// Moved objects within the same section.
				if let indexPath = originOfMovedObjects[reference], indexPath.row != r {
					let from = indexPath
					let to = IndexPath(row: r, section: s)
					indexPathsOfMovedRows.append((from, to))
					continue
				}

				// Moved objects across sections.
				if inboundObjects.value.contains(reference) {
					let origin = originOfSectionChangedObjects[reference]!

					if indiceOfDeletedSections.contains(origin.section) {
						/// The originated section no longer exists, treat it as an inserted row.
						let indexPath = IndexPath(row: r, section: s)
						indexPathsOfInsertedRows.append(indexPath)
						continue
					}

					let to = IndexPath(row: r, section: s)
					indexPathsOfMovedRows.append((origin, to))
					continue
				}
			}
		}

		let resultSetChanges: SectionedCollectionChanges
		resultSetChanges = SectionedCollectionChanges(
			deletedRows: indexPathsOfDeletedRows,
			insertedRows: indexPathsOfInsertedRows,
			updatedRows: indexPathsOfUpdatedRows,
			movedRows: indexPathsOfMovedRows,
			deletedSections: indiceOfDeletedSections,
			insertedSections: indiceOfInsertedSections
		)

		return resultSetChanges
	}

	deinit {
		eventObserver.sendCompleted()
		releaseCache()
	}
}

extension ObjectCollection: SectionedCollection {
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

	public func index(_ i: IndexPath, offsetBy n: Int) -> IndexPath {
		if n == 0 {
			return i
		}

		var position = i
		var offset = n

		while (n > 0 && offset >= 0) || (n < 0 && offset <= 0) {
			let section = sections[position.section]
			let delta: Int

			if n > 0 {
				let limit = section.index(before: section.endIndex)
				delta = limit - position.row + offset
			} else {
				let limit = section.startIndex
				delta = position.row + offset - limit
			}

			if delta >= 0 {
				return IndexPath(row: position.row + offset, section: position.section)
			}

			if n > 0 {
				offset = delta
				position = IndexPath(row: -1, section: position.section + 1)
			} else {
				offset = -delta
				position = IndexPath(row: sections[position.section - 1].endIndex, section: position.section - 1)
			}
		}

		fatalError("Index out of bound.")
	}

	public subscript(row row: Int, section section: Int) -> E {
		prefetcher?.acknowledgeNextAccess(at: row, in: section)
		return sections[section][row].wrapped
	}

	public func sectionName(for section: Int) -> String? {
		return sections[section].name
	}

	public func rowCount(for section: Int) -> Int {
		return sections[section].count
	}

	public func indexPath(of element: E) -> IndexPath? {
		let name = sectionName(of: element)
		if let sectionIndex = sections.index(of: name, ascending: sortsAscendingSectionName) {
			if let objectIndex = sections[sectionIndex].storage.index(of: ObjectReference<E>(element), with: objectComparer) {
				return IndexPath(row: objectIndex, section: sectionIndex)
			}
		}

		return nil
	}
}

internal protocol SectionNameProviding {
	var name: String? { get }
}


internal struct SectionKey: Hashable, SectionNameProviding {
	let name: String?
	let hashValue: Int

	init(_ name: String?) {
		self.name = name
		self.hashValue = (name?.hashValue ?? -1) + 1
	}

	static func ==(left: SectionKey, right: SectionKey) -> Bool {
		return left.name == right.name
	}
}

internal final class ObjectCollectionSection<E: NSManagedObject>: RandomAccessCollection, SectionNameProviding {
	typealias Indices = DefaultRandomAccessIndices<ObjectCollectionSection>

	let name: String?
	var storage: [ObjectReference<E>]

	init(name: String?, array: [ObjectReference<E>]) {
		self.name = name
		self.storage = array
	}

	var startIndex: Int {
		return 0
	}

	var endIndex: Int {
		return storage.count
	}

	subscript(position: Int) -> ObjectReference<E> {
		return storage[position]
	}

	func index(after i: Int) -> Int {
		return i + 1
	}

	func index(before i: Int) -> Int {
		return i - 1
	}

	func index(_ i: Int, offsetBy n: Int) -> Int {
		return i + n
	}

	func distance(from start: Int, to end: Int) -> Int {
		return end - start
	}

	func copy() -> ObjectCollectionSection {
		return ObjectCollectionSection(name: name, array: storage)
	}
}

protocol ObjectReferenceProtocol: Hashable {
	associatedtype Object: NSManagedObject

	var reference: ObjectReference<Object> { get }
}

internal struct ObjectReference<E: NSManagedObject>: ObjectReferenceProtocol {
	unowned(unsafe) let wrapped: E
	let hashValue: Int

	var reference: ObjectReference<E> {
		return self
	}

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
		// Objects always have the same instance of object ID.
		return left.wrapped === right.wrapped
	}
}

internal struct ObjectSnapshot {
	let wrapped: [AnyObject]

	init(_ dictionary: [AnyObject]) {
		wrapped = dictionary
	}
}

@objc protocol NSObjectComparing: class {
	func compare(_ other: AnyObject?) -> ComparisonResult
}

internal final class Comparer<E: NSManagedObject> {
	let isAscending: [(Int, Bool)]
	weak var collection: ObjectCollection<E>!

	init(_ sortDescriptors: [NSSortDescriptor], groupsBySection: Bool) {
		var index = groupsBySection ? 1 : 0
		self.isAscending = sortDescriptors.map {
			defer { index += 1 }
			return (index, $0.ascending)
		}
	}

	func compare<R: ObjectReferenceProtocol>(_ left: R, to right: R) -> ComparisonResult where R.Object == E {
		let left = collection.objectCache[left.reference]!
		let right = collection.objectCache[right.reference]!

		for (i, isAscending) in isAscending {
			let order = left.wrapped[i].compare(right.wrapped[i])
			if order != .orderedSame {
				return isAscending ? order : (order == .orderedAscending ? .orderedDescending : .orderedAscending)
			}
		}

		return .orderedSame
	}
}
