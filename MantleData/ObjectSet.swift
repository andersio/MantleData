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
/// - Warning:	 This class is not thread-safe. Use it only in the associated NSManagedObjectContext.
final public class ObjectSet<E: NSManagedObject>: Base {
	private typealias _IndexPath = ReactiveSetIndexPath<Index, Generator.Element.Index>

	public let fetchRequest: NSFetchRequest
	public let entity: NSEntityDescription

	public let shouldExcludeUpdatedRows: Bool
	public let sectionNameKeyPath: String?

	private let sectionNameOrdering: NSComparisonResult
	private let objectSortDescriptors: [NSSortDescriptor]
	private let sortKeys: [String]
	private let sortKeyComponents: [(String, [String])]
	private let sortOrderAffectingRelationships: [String]
	private let sortKeysInSections: [String]

	internal var sections: [ObjectSetSection<E>] = []
	private var objectCache = [NSManagedObjectID: [String: AnyObject]]()

	private var temporaryObjects = [E: NSManagedObjectID]()
	private var isAwaitingContextSave = false

	// An ObjectSet retains the managed object context.
	private(set) public weak var context: NSManagedObjectContext!

	private var eventSignal = Atomic<Signal<ReactiveSetEvent<Index, Generator.Element.Index>, NoError>?>(nil)
	private var eventObserver: Observer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError>? = nil {
		willSet {
			if eventObserver == nil && newValue != nil {
				NSNotificationCenter.defaultCenter().addObserver(self,
				                                                 selector: #selector(ObjectSet.process(objectsDidChangeNotification:)),
				                                                 name: NSManagedObjectContextObjectsDidChangeNotification,
				                                                 object: context)

				context.willDeinitProducer
					.takeUntil(willDeinitProducer)
					.startWithCompleted { [weak self] in
						if let strongSelf = self {
							NSNotificationCenter.defaultCenter().removeObserver(strongSelf,
																																	name: NSManagedObjectContextObjectsDidChangeNotification,
																																	object: strongSelf.context)
						}
				}
			}
		}
	}

	public var eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError> {
		return SignalProducer { observer, disposable in
			var _signal: Signal<ReactiveSetEvent<Index, Generator.Element.Index>, NoError>!

			self.eventSignal.modify { oldValue in
				if let oldValue = oldValue {
					_signal = oldValue
					return oldValue
				} else {
					let (signal, observer) = Signal<ReactiveSetEvent<Index, Generator.Element.Index>, NoError>.pipe()
					self.eventObserver = observer
					_signal = signal
					return signal
				}
			}

			disposable += _signal.observe(observer)
		}
	}

	public init(for request: NSFetchRequest,
							in context: NSManagedObjectContext,
							sectionNameKeyPath: String? = nil,
							excludeUpdatedRowsInEvents: Bool = true) {
		self.context = context
		self.fetchRequest = request.copy() as! NSFetchRequest
		self.entity = self.fetchRequest.entity!

		self.shouldExcludeUpdatedRows = excludeUpdatedRowsInEvents

		self.sectionNameKeyPath = sectionNameKeyPath

		precondition(request.sortDescriptors != nil,
		             "ObjectSet requires sort descriptors to work.")
		precondition(request.sortDescriptors!.reduce(true) { reducedValue, descriptor in
			return reducedValue && descriptor.key!.componentsSeparatedByString(".").count <= 2
		}, "ObjectSet does not support sorting on to-one key paths deeper than 1 level.")

		if sectionNameKeyPath != nil {
			precondition(request.sortDescriptors!.count >= 2, "Unsufficient number of sort descriptors.")
			self.sectionNameOrdering = fetchRequest.sortDescriptors!.first!.ascending ? .OrderedAscending : .OrderedDescending
			self.objectSortDescriptors = Array(fetchRequest.sortDescriptors!.dropFirst())
		} else {
			self.sectionNameOrdering = .OrderedSame
			self.objectSortDescriptors = fetchRequest.sortDescriptors ?? []
		}

		sortKeys = fetchRequest.sortDescriptors!.map { $0.key! }
		sortKeysInSections = Array(sortKeys.dropFirst())
		sortKeyComponents = sortKeys.map { ($0, $0.componentsSeparatedByString(".")) }
		sortOrderAffectingRelationships = Array(Set(sortKeyComponents.flatMap { $0.1.count > 1 ? $0.1[0] : nil }))

		super.init()
	}

	public func fetch() throws {
		func completionBlock(result: NSAsynchronousFetchResult) {
			self.sectionize(using: result.finalResult as? [[String: AnyObject]] ?? [])
		}

		context.perform {
			let description = NSExpressionDescription()
			description.name = "objectID"
			description.expression = NSExpression.expressionForEvaluatedObject()
			description.expressionResultType = .ObjectIDAttributeType

			var fetching = [AnyObject]()

			fetching.append(description)
			fetching.appendContentsOf(sortOrderAffectingRelationships as [AnyObject])
			fetching.appendContentsOf(sortKeys.map { NSString(string: $0) })

			self.fetchRequest.propertiesToFetch = fetching
			self.fetchRequest.resultType = .DictionaryResultType

			let asyncRequest = NSAsynchronousFetchRequest(fetchRequest: self.fetchRequest, completionBlock: completionBlock)

			do {
				try self.context.executeRequest(asyncRequest)
			} catch let error as NSError {
				fatalError("\(error.description)")
			}
		}
	}

	private func sectionize(using resultDictionaries: [[String: AnyObject]]) {
		sections = []

		if !resultDictionaries.isEmpty {
			var ranges: [(range: Range<Int>, name: ReactiveSetSectionName)] = []

			// Objects are sorted wrt sections already.
			for position in resultDictionaries.indices {
				if let sectionNameKeyPath = sectionNameKeyPath {
					let sectionName = ReactiveSetSectionName(converting: resultDictionaries[position][sectionNameKeyPath])

					if ranges.isEmpty || ranges.last?.name != sectionName {
						ranges.append((range: position ..< position + 1, name: sectionName))
					} else {
						ranges[ranges.endIndex - 1].range.endIndex += 1
					}
				} else {
					if ranges.isEmpty {
						ranges.append((range: position ..< position + 1, name: ReactiveSetSectionName()))
					} else {
						ranges[0].range.endIndex += 1
					}
				}
			}

			sections.reserveCapacity(ranges.count)

			var inMemoryChangedObjects = [ReactiveSetSectionName: Set<NSManagedObjectID>]()

			for (range, name) in ranges {
				var objectIDs = ContiguousArray<NSManagedObjectID>()
				objectIDs.reserveCapacity(range.count)

				for position in range {
					let id = resultDictionaries[position]["objectID"] as! NSManagedObjectID

					func markAsChanged(object registeredObject: E) {
						updateCache(for: registeredObject.objectID, with: registeredObject)
						if let sectionNameKeyPath = sectionNameKeyPath {
							let sectionName = ReactiveSetSectionName(converting: registeredObject.valueForKeyPath(sectionNameKeyPath))
							inMemoryChangedObjects.insert(registeredObject.objectID, intoSetOf: sectionName)
						} else {
							inMemoryChangedObjects.insert(registeredObject.objectID, intoSetOf: ReactiveSetSectionName())
						}
					}

					/// If an object is registered with the context and has changes in key paths affecting
					/// the sort order, update the cache but exclude the object from the set and handle it later.

					if let registeredObject = context.objectRegisteredForID(id) as? E {
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
							relatedObject = context.objectRegisteredForID(relationshipID) where relatedObject.updated {
							return true
						}
						return false
					}

					if hasUpdatedRelationships {
						let object = context.objectWithID(id) as! E
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
				mergeChanges(inserted: inMemoryChangedObjects)
			}
		}

		eventObserver?.sendNext(.reloaded)
	}

	private func registerTemporaryObject(object: E) {
		temporaryObjects[object] = object.objectID

		if !isAwaitingContextSave {
			NSNotificationCenter.defaultCenter()
				.addObserver(self,
										 selector: #selector(handle(contextDidSaveNotification:)),
										 name: NSManagedObjectContextDidSaveNotification,
										 object: context)

			isAwaitingContextSave = true
		}
	}

	@objc private func handle(contextDidSaveNotification notification: NSNotification) {
		guard let userInfo = notification.userInfo else {
			return
		}

		if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
			for object in insertedObjects {
				guard let object = object as? E else {
					continue
				}

				if let temporaryId = temporaryObjects[object] {
					assert(!object.objectID.temporaryID)

					/// Find the position of the object.
					let sectionIndex = indexOfSection(with: sectionName(of: object)!)!
					let objectIndex = sections[sectionIndex].storage.index(of: temporaryId,
					                                                       using: objectSortDescriptors,
					                                                       with: objectCache)!

					/// Update the object and the cache with the permanent ID.
					sections[sectionIndex].storage[objectIndex] = object.objectID
					clearCache(for: temporaryId)
					updateCache(for: object.objectID, with: object)
				}
			}
		}

		temporaryObjects = [:]

		NSNotificationCenter.defaultCenter()
			.removeObserver(self,
										  name: NSManagedObjectContextDidSaveNotification,
										  object: context)
		isAwaitingContextSave = false
	}

	private func updateCache(for objectID: NSManagedObjectID, with object: NSObject) {
		var dictionary = [String: AnyObject]()

		for sortKey in sortKeys {
			dictionary[sortKey] = object.valueForKeyPath(sortKey) ?? NSNull()
		}

		objectCache[objectID] = dictionary
	}

	private func clearCache(for objectID: NSManagedObjectID) {
		objectCache.removeValueForKey(objectID)
	}

	private func _sectionName(of object: E) -> ReactiveSetSectionName {
		if let keyPath = self.sectionNameKeyPath {
			return ReactiveSetSectionName(converting: object.valueForKeyPath(keyPath))
		}

		return ReactiveSetSectionName()
	}

	private func predicateMatching(object: NSObject) -> Bool {
		return fetchRequest.predicate?.evaluateWithObject(object) ?? true
	}

	/// - Returns: A qualifying object for `self`. `nil` if the object is not qualified.
	private func qualifyingObject(object: NSManagedObject) -> E? {
		if let object = object as? E {
			if predicateMatching(object) {
				return object
			}
		}
		return nil
	}

	/// Merge changes since last posting of NSManagedContextObjectsDidChangeNotification.
	/// This method should not mutate the `sections` array.
	@objc private func process(objectsDidChangeNotification notification: NSNotification) {
		guard let eventObserver = eventObserver else {
			return
		}

		guard let userInfo = notification.userInfo else {
			return
		}

		/// If all objects are invalidated. We perform a refetch instead.
		guard !userInfo.keys.contains(NSInvalidatedAllObjectsKey) else {
			try! fetch()
			return
		}

		/// Reference sections by name, since these objects may lead to creating a new section.
		var insertedObjects = [ReactiveSetSectionName: Set<NSManagedObjectID>]()

		/// Referencing sections by the index in snapshot.
		var sectionChangedObjects = sections.indices.map { _ in Set<Int>() }
		var deletedObjects = sections.indices.map { _ in [Int]() }
		var updatedObjects = sections.indices.map { _ in Set<NSManagedObjectID>() }
		var sortOrderAffectingObjects = sections.indices.map { _ in Set<Int>() }

		func sortOrderIsAffected(by object: E, against snapshot: [String: AnyObject]) -> Bool {
			for key in sortKeysInSections {
				if let index = snapshot.indexForKey(key) {
					if !object.valueForKeyPath(key)!.isEqual(snapshot[index].1) {
						return true
					}
				}
			}

			return false
		}

		func processDeletedObjects(set: Set<NSManagedObject>) {
			for object in set {
				guard let object = object as? E else {
					continue
				}

				if let cacheIndex = objectCache.indexForKey(object.objectID) {
					let sectionName: ReactiveSetSectionName

					if let sectionNameKeyPath = sectionNameKeyPath {
						sectionName = ReactiveSetSectionName(converting: objectCache[cacheIndex].1[sectionNameKeyPath])
					} else {
						sectionName = ReactiveSetSectionName()
					}

					if let index = indexOfSection(with: sectionName) {
						if let objectIndex = sections[index].storage.index(of: object.objectID,
						                                                   using: objectSortDescriptors,
						                                                   with: objectCache) {
							deletedObjects.orderedInsert(objectIndex, toCollectionAt: index)
							clearCache(for: object.objectID)
						}
					}
				}
			}
		}

		func processUpdatedObjects(set: Set<NSManagedObject>) {
			for object in set {
				guard let object = object as? E else {
					continue
				}

				let cacheIndex = objectCache.indexForKey(object.objectID)

				if !predicateMatching(object) {
					guard let cacheIndex = cacheIndex else {
						continue
					}

					/// The object no longer qualifies. Delete it from the ObjectSet.
					let sectionName: ReactiveSetSectionName

					if let sectionNameKeyPath = sectionNameKeyPath {
						sectionName = ReactiveSetSectionName(converting: objectCache[cacheIndex].1[sectionNameKeyPath])
					} else {
						sectionName = ReactiveSetSectionName()
					}

					if let index = indexOfSection(with: sectionName) {
						/// Use binary search, but compare against the previous values dictionary.
						if let objectIndex = sections[index].storage.index(of: object.objectID,
						                                                   using: objectSortDescriptors,
						                                                   with: objectCache) {
							deletedObjects.orderedInsert(objectIndex, toCollectionAt: index)
							clearCache(for: object.objectID)
							continue
						}
					}
				} else if let cacheIndex = cacheIndex {
					/// The object still qualifies. Does it have any change affecting the sort order?
					let currentSectionName: ReactiveSetSectionName

					if let sectionNameKeyPath = sectionNameKeyPath {
						let previousSectionName = ReactiveSetSectionName(converting: objectCache[cacheIndex].1[sectionNameKeyPath])
						currentSectionName = _sectionName(of: object)

						guard previousSectionName == currentSectionName else {
							guard let previousSectionIndex = sections.indexOfSection(with: currentSectionName) else {
								preconditionFailure("current section name is supposed to exist, but not found.")
							}

							guard let objectIndex = sections[previousSectionIndex].storage.index(of: object.objectID,
							                                                                     using: objectSortDescriptors,
							                                                                     with: objectCache) else {
								preconditionFailure("An object should be in section \(previousSectionIndex), but it cannot be found. (ID: \(object.objectID.URIRepresentation()))")
							}

							sectionChangedObjects.insert(objectIndex, intoSetAt: previousSectionIndex)
							updateCache(for: object.objectID, with: object)
							continue
						}
					} else {
						currentSectionName = ReactiveSetSectionName()
					}

					guard let currentSectionIndex = indexOfSection(with: currentSectionName) else {
						preconditionFailure("current section name is supposed to exist, but not found.")
					}

					guard !sortOrderIsAffected(by: object, against: objectCache[cacheIndex].1) else {
						guard let objectIndex = sections[currentSectionIndex].storage.index(of: object.objectID,
						                                                                     using: objectSortDescriptors,
						                                                                     with: objectCache) else {
							preconditionFailure("An object should be in section \(currentSectionIndex), but it cannot be found. (ID: \(object.objectID.URIRepresentation()))")
						}

						sortOrderAffectingObjects.insert(objectIndex, intoSetAt: currentSectionIndex)
						updateCache(for: object.objectID, with: object)
						continue
					}

					if !shouldExcludeUpdatedRows {
						updatedObjects.insert(object.objectID, intoSetAt: currentSectionIndex)
					}
				} else {
					let currentSectionName = _sectionName(of: object)
					insertedObjects.insert(object.objectID, intoSetOf: currentSectionName)
					updateCache(for: object.objectID, with: object)
					continue
				}
			}
		}

		if let _insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
			for object in _insertedObjects {
				if let object = qualifyingObject(object) {
					let name = _sectionName(of: object)
					insertedObjects.insert(object.objectID, intoSetOf: name)
					updateCache(for: object.objectID, with: object)

					if object.objectID.temporaryID {
						registerTemporaryObject(object)
					}
				}
			}
		}

		if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
			processDeletedObjects(deletedObjects)
		}

		if let invalidatedObjects = userInfo[NSInvalidatedObjectsKey] as? Set<NSManagedObject> {
			processDeletedObjects(invalidatedObjects)
		}

		if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(updatedObjects)
		}

		if let refreshedObjects = userInfo[NSRefreshedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(refreshedObjects)
		}

		if let changes = mergeChanges(inserted: insertedObjects,
																  deleted: deletedObjects,
																  updated: updatedObjects,
																  sortOrderAffecting: sortOrderAffectingObjects,
																  sectionChanged: sectionChangedObjects) {
			eventObserver.sendNext(.updated(changes))
		}
	}

	private func mergeChanges(inserted insertedObjects: [ReactiveSetSectionName: Set<NSManagedObjectID>]? = nil,
														deleted deletedObjects: [[Int]]? = nil,
														updated updatedObjects: [Set<NSManagedObjectID>]? = nil,
														sortOrderAffecting sortOrderAffectingObjects: [Set<Int>]? = nil,
														sectionChanged sectionChangedObjects: [Set<Int>]? = nil)
														-> ReactiveSetChanges<Index, Generator.Element.Index>? {
		guard let eventObserver = eventObserver else {
			return nil
		}

		let insertedObjects = insertedObjects ?? [:]
		let sectionChangedObjects = sectionChangedObjects ?? sections.indices.map { _ in Set<Int>() }
		let deletedObjects = deletedObjects ?? sections.indices.map { _ in [Int]() }
		let updatedObjects = updatedObjects ?? sections.indices.map { _ in Set<NSManagedObjectID>() }
		let sortOrderAffectingObjects = sortOrderAffectingObjects ?? sections.indices.map { _ in Set<Int>() }

		/// Process deletions first, and buffer moves and insertions.
		let sectionSnapshots = sections

		let insertedObjectsCount = insertedObjects.reduce(0) { $0 + $1.1.count }
		let deletedObjectsCount = deletedObjects.reduce(0) { $0 + $1.count }
		let sectionChangedObjectsCount = sectionChangedObjects.reduce(0) { $0 + $1.count }
		let updatedObjectsCount = updatedObjects.reduce(0) { $0 + $1.count }
		let sortOrderAffectingObjectsCount = sortOrderAffectingObjects.reduce(0) { $0 + $1.count }

		var inboundObjects = [ReactiveSetSectionName: Set<NSManagedObjectID>]()
		var inPlaceMovingObjects = sectionSnapshots.indices.map { _ in Set<NSManagedObjectID>() }
		var deletingIndexPaths = (0 ..< sectionSnapshots.count).map { _ in [Int]() }

		var originOfSectionChangedObjects = [NSManagedObjectID: _IndexPath](minimumCapacity: sectionChangedObjectsCount)
		var originOfMovedObjects = [NSManagedObjectID: _IndexPath](minimumCapacity: sortOrderAffectingObjectsCount)

		var indexPathsOfInsertedRows = [_IndexPath]()
		var indexPathsOfUpdatedRows = [_IndexPath]()
		var indexPathsOfMovedRows = [(from: _IndexPath, to: _IndexPath)]()

		var indiceOfDeletedSections = [Index]()
		var indiceOfInsertedSections = [Index]()

		indexPathsOfInsertedRows.reserveCapacity(insertedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(sectionChangedObjectsCount + sortOrderAffectingObjectsCount)

		/// MARK: Handle deletions.

		var indexPathsOfDeletedRows = deletedObjects.enumerate().flatMap { (sectionIndex, indice) in
			return indice.map { objectIndex -> _IndexPath in
				deletingIndexPaths.orderedInsert(objectIndex, toCollectionAt: sectionIndex, ascending: false)
				return _IndexPath(section: sectionIndex, row: objectIndex)
			}
		}

		for (previousSectionIndex, indices) in sectionChangedObjects.enumerate() {
			for previousObjectIndex in indices {
				let id = sectionSnapshots[previousSectionIndex].storage[previousObjectIndex]
				deletingIndexPaths.orderedInsert(previousObjectIndex, toCollectionAt: previousSectionIndex, ascending: false)

				let indexPath = ReactiveSetIndexPath(section: previousSectionIndex, row: previousObjectIndex)
				originOfSectionChangedObjects[id] = indexPath

				let newSectionName = _sectionName(of: context.objectRegisteredForID(id) as! E)
				inboundObjects.insert(id, intoSetOf: newSectionName)
			}
		}

		for (sectionIndex, indices) in sortOrderAffectingObjects.enumerate() {
			for previousObjectIndex in indices {
				let id = sectionSnapshots[sectionIndex].storage[previousObjectIndex]
				deletingIndexPaths.orderedInsert(previousObjectIndex, toCollectionAt: sectionIndex, ascending: false)

				let indexPath = ReactiveSetIndexPath(section: sectionIndex, row: previousObjectIndex)
				originOfMovedObjects[id] = indexPath

				inPlaceMovingObjects.insert(id, intoSetAt: sectionIndex)
			}
		}

		for sectionIndex in deletingIndexPaths.indices {
			deletingIndexPaths[sectionIndex].forEach {
				sections[sectionIndex].removeAtIndex($0)
			}
		}

		for index in sections.indices.reverse() {
			if sections[index].count == 0 && inPlaceMovingObjects[index].count == 0 {
				sections.removeAtIndex(index)
				indiceOfDeletedSections.append(index)
			}
		}

		/// MARK: Handle insertions.

		func insert(ids: Set<NSManagedObjectID>, intoSectionFor name: ReactiveSetSectionName) {
			if let sectionIndex = indexOfSection(with: name) {
				for id in ids {
					sections[sectionIndex].storage.insert(id, using: objectSortDescriptors, with: objectCache)
				}
			} else {
				let section = ObjectSetSection(at: -1,
				                               name: name,
				                               array: ContiguousArray(ids),
				                               in: self)
				sections.insert(section,
				                name: name,
				                ordering: sectionNameOrdering)
			}
		}

		for (sectionName, objects) in insertedObjects {
			insert(objects, intoSectionFor: sectionName)
		}

		for (sectionName, objects) in inboundObjects {
			insert(objects, intoSectionFor: sectionName)
		}

		/// MARK: Index generating full pass.

		for sectionIndex in sections.indices {
			let sectionName = sections[sectionIndex].name
			let previousSectionIndex = sectionSnapshots.indexOfSection(with: sectionName)

			if let previousSectionIndex = previousSectionIndex {
				for id in inPlaceMovingObjects[previousSectionIndex] {
					sections[sectionIndex].storage.insert(id, using: objectSortDescriptors, with: objectCache)
				}
			} else {
				indiceOfInsertedSections.append(sectionIndex)
			}

			let insertedObjects = insertedObjects[sectionName] ?? []
			let inboundObjects = inboundObjects[sectionName] ?? []

			for (objectIndex, object) in sections[sectionIndex].storage.enumerate() {
				if !shouldExcludeUpdatedRows, let oldSectionIndex = previousSectionIndex where updatedObjects[oldSectionIndex].contains(object) {
					let indexPath = _IndexPath(section: sectionIndex, row: objectIndex)
					indexPathsOfUpdatedRows.append(indexPath)
					continue
				}

				if previousSectionIndex != nil && insertedObjects.contains(object) {
					let indexPath = _IndexPath(section: sectionIndex, row: objectIndex)
					indexPathsOfInsertedRows.append(indexPath)
					continue
				}

				if let indexPath = originOfMovedObjects[object] {
					let from = indexPath
					let to = _IndexPath(section: sectionIndex, row: objectIndex)
					indexPathsOfMovedRows.append((from, to))

					continue
				}

				if inboundObjects.contains(object) {
					let origin = originOfSectionChangedObjects[object]!

					if indiceOfDeletedSections.contains(origin.section) {
						/// The originated section no longer exists, treat it as an inserted row.
						let indexPath = _IndexPath(section: sectionIndex, row: objectIndex)
						indexPathsOfInsertedRows.append(indexPath)
						continue
					}

					if indiceOfInsertedSections.contains(sectionIndex) {
						/// The target section is newly created.
						continue
					}

					let to = _IndexPath(section: sectionIndex, row: objectIndex)
					indexPathsOfMovedRows.append((origin, to))
					continue
				}
			}
		}

		// Update the sections' `indexInSet`.
		for position in sections.indices {
			sections[position].indexInSet = position
		}

		let resultSetChanges: ReactiveSetChanges<Index, Generator.Element.Index>
		resultSetChanges = ReactiveSetChanges(insertedRows: indexPathsOfInsertedRows.isEmpty ? nil : indexPathsOfInsertedRows,
		                                      deletedRows: indexPathsOfDeletedRows.isEmpty ? nil : indexPathsOfDeletedRows,
		                                      movedRows: indexPathsOfMovedRows.isEmpty ? nil : indexPathsOfMovedRows,
		                                      updatedRows: indexPathsOfUpdatedRows.isEmpty ? nil : indexPathsOfUpdatedRows,
		                                      insertedSections: indiceOfInsertedSections.isEmpty ? nil : indiceOfInsertedSections,
		                                      deletedSections: indiceOfDeletedSections.isEmpty ? nil : indiceOfDeletedSections)

		return resultSetChanges
	}

	deinit {
		eventObserver?.sendCompleted()
	}
}

extension ObjectSet: ReactiveSet {
	public typealias Index = Int
	public typealias Generator = AnyReactiveSetIterator<ObjectSetSection<E>>
	public typealias SubSequence = ArraySlice<ObjectSetSection<E>>

	// Indexable

	public var startIndex: Int {
		return sections.startIndex
	}

	public var endIndex: Int {
		return sections.endIndex
	}

	public subscript(index: Int) -> ObjectSetSection<E> {
		return sections[index]
	}

	// SequenceType

	public func generate() -> AnyReactiveSetIterator<ObjectSetSection<E>> {
		var index = startIndex
		let limit = endIndex

		return AnyReactiveSetIterator {
			defer { index = index.successor() }
			return index < limit ? self[index] : nil
		}
	}

	// CollectionType

	public subscript(bounds: Range<Int>) -> ArraySlice<ObjectSetSection<E>> {
		return sections[bounds]
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return _sectionName(of: object)
	}
}