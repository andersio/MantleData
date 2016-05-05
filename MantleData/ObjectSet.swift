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
/// You **must** merge changes from other contexts through the MantleData extension
/// to `NSManagedObjectContext`, since it relies on a custom notification posted before
/// the context merging remote changes to compute changes correctly.
///
/// On the other hand, `ObjectSet` **does not support** sorting or section name on key paths that
/// are deeper than one level of one-to-one relationships.
///
/// As for observing changes of individual objects, `ObjectSet` by default does not emit any
/// index paths for updated rows based on the assumed use of KVO-based bindings. You may override
/// this behavior by setting `excludeUpdatedRowsInEvents` in the initialiser as `false`.
///
/// - Warning:	 This class is not thread-safe. Use it only in the associated NSManagedObjectContext.
final public class ObjectSet<E: NSManagedObject>: Base {
	public let fetchRequest: NSFetchRequest
	public let entity: NSEntityDescription

	public let shouldExcludeUpdatedRows: Bool

	public let sectionNameKeyPath: String?
	private let _sectionNameKeyPath: [String]?
	public let defaultSectionName: String

	public let sectionNameOrdering: NSComparisonResult
	public let objectSortDescriptors: [NSSortDescriptor]
	public let sortKeys: [String]
	public let sortKeyComponents: [(String, [String])]
	public let sortKeysInSections: [String]

	// An ObjectSet retains the managed object context.
	private(set) public weak var context: NSManagedObjectContext!

	private var eventSignal = Atomic<Signal<ReactiveSetEvent, NoError>?>(nil)
	private var eventObserver: Observer<ReactiveSetEvent, NoError>? = nil {
		willSet {
			if eventObserver == nil && newValue != nil {
				NSNotificationCenter.defaultCenter().addObserver(self,
				                                                 selector: #selector(ObjectSet.preprocessRemoteOriginatedChanges(from:)),
				                                                 name: MantleData.objectContextWillMergeChangesNotification,
				                                                 object: context)
				NSNotificationCenter.defaultCenter().addObserver(self,
				                                                 selector: #selector(ObjectSet.mergeChanges(from:)),
				                                                 name: NSManagedObjectContextObjectsDidChangeNotification,
				                                                 object: context)

				context.willDeinitProducer
					.takeUntil(willDeinitProducer)
					.startWithCompleted { [weak self] in
						if let strongSelf = self {
							NSNotificationCenter.defaultCenter().removeObserver(strongSelf,
																																	name: objectContextWillMergeChangesNotification,
																																	object: strongSelf.context)
							NSNotificationCenter.defaultCenter().removeObserver(strongSelf,
																																	name: NSManagedObjectContextObjectsDidChangeNotification,
																																	object: strongSelf.context)
						}
				}
			}
		}
	}

	public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return SignalProducer { observer, disposable in
			var _signal: Signal<ReactiveSetEvent, NoError>!

			self.eventSignal.modify { oldValue in
				if let oldValue = oldValue {
					_signal = oldValue
					return oldValue
				} else {
					let (signal, observer) = Signal<ReactiveSetEvent, NoError>.pipe()
					self.eventObserver = observer
					_signal = signal
					return signal
				}
			}

			disposable += _signal.observe(observer)
		}
	}

	private var sections: [ObjectSetSection<E>] = []

	private var isMergingRemoteChanges: Bool = false

	public init(for request: NSFetchRequest, in context: NSManagedObjectContext, sectionNameKeyPath: String? = nil, defaultSectionName: String = "", excludeUpdatedRowsInEvents: Bool = true) {
		self.context = context
		self.fetchRequest = request.copy() as! NSFetchRequest
		self.entity = self.fetchRequest.entity!

		self.shouldExcludeUpdatedRows = excludeUpdatedRowsInEvents

		self.defaultSectionName = defaultSectionName
		self.sectionNameKeyPath = sectionNameKeyPath
		self._sectionNameKeyPath = sectionNameKeyPath?.componentsSeparatedByString(".")

		precondition(request.sortDescriptors != nil,
		             "ObjectSet requires sort descriptors to work.")
		precondition(context.stalenessInterval < 0,
		             "ObjectSet only works with contexts allowing infinite staleness.")
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

		self.fetchRequest.relationshipKeyPathsForPrefetching = sortKeyComponents.flatMap { $0.1.count > 1 ? $0.1[0] : nil }

		super.init()

		self.fetchRequest.resultType = .ManagedObjectResultType
	}

	deinit {
		for section in sections {
			for object in section {
				context.refreshObject(object, mergeChanges: false)
			}
		}
		eventObserver?.sendCompleted()
	}

	public func fetch() throws {
		func completionBlock(result: NSAsynchronousFetchResult) {
			self.sectionize(using: result.finalResult as? [E] ?? [])
			eventObserver?.sendNext(.Reloaded)
		}

		context.performBlock {
			do {
				let result = try self.context.executeFetchRequest(self.fetchRequest)
				self.sectionize(using: result as! [E])
				self.eventObserver?.sendNext(.Reloaded)
			} catch let error as NSError {
				fatalError("\(error.description)")
			}
		}
	}

	private func sectionize(using fetchedObjects: [E]) {
		guard let keyPath = sectionNameKeyPath else {
			sections = [ObjectSetSection(name: ReactiveSetSectionName(),
				array: ContiguousArray(fetchedObjects))]

			return
		}

		sections = []

		if !fetchedObjects.isEmpty {
			var ranges: [(range: Range<Int>, name: ReactiveSetSectionName)] = []

			// Objects are sorted wrt to sections already.
			for position in fetchedObjects.startIndex ..< fetchedObjects.endIndex {
				/// Core Data does not fault in relationships even through it is prefetched
				/// and accessible via KVC. This would cause any future preprocessing
				///	before merging remote changes in `preprocessRemoteOriginatedChanges`
				///	to fail.
				///
				/// Therefore, the sort/section name affecting relationships must be
				/// explicitly retained.

				let sectionName = ReactiveSetSectionName(converting: fetchedObjects[position].valueForKeyPath(keyPath))

				if ranges.isEmpty || ranges.last?.name != sectionName {
					ranges.append((range: position ..< position + 1, name: sectionName))
				} else {
					ranges[ranges.endIndex - 1].range.endIndex += 1
				}
			}

			sections.reserveCapacity(ranges.count)

			for (range, name) in ranges {
				let section = ObjectSetSection(name: name, array: ContiguousArray(fetchedObjects[range]))
				sections.append(section)
			}
		}
	}

	private func sectionName(from object: E) -> ReactiveSetSectionName {
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

	@objc private func preprocessRemoteOriginatedChanges(from notification: NSNotification) {
		isMergingRemoteChanges = true
	}

	/// Merge changes since last posting of NSManagedContextObjectsDidChangeNotification.
	@objc private func mergeChanges(from notification: NSNotification) {
		defer {
			isMergingRemoteChanges = false
		}

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

		/// Process deletions first, and buffer moves and insertions.
		let sectionSnapshots = sections

		/// Reference sections by name, since these objects may lead to creating a new section.
		var insertedObjects = [ReactiveSetSectionName: Set<E>]()

		/// Referencing sections by the index in snapshot.
		var sectionChangedObjects = sectionSnapshots.indices.map { _ in Set<E>() }
		var deletedObjects = sectionSnapshots.indices.map { _ in [Int]() }
		var updatedObjects = sectionSnapshots.indices.map { _ in Set<E>() }
		var sortOrderAffectingObjects = sectionSnapshots.indices.map { _ in Set<E>() }

		func processDeletedObjects(set: Set<NSManagedObject>, isInvalidating: Bool) {
			/// Object invalidation always originates from the local context.
			if !isInvalidating && isMergingRemoteChanges {
				/// Must compare the object pointer, since no sufficient information is available for
				/// remotely deleted objects.

				for object in set {
					guard let object = object as? E else {
						continue
					}

					for sectionIndex in sections.indices {
						if let objectIndex = sections[sectionIndex].indexOf(object) {
							deletedObjects.orderedInsert(objectIndex, toCollectionAt: sectionIndex)
						}
					}
				}
			} else {
				var filteredCollection = [E: [String: AnyObject]]()

				for object in set {
					guard let object = object as? E else {
						continue
					}

					filteredCollection[object] = computeSnapshot(for: object)
				}

				for (object, snapshot) in filteredCollection {

					/// If it is locally deleted or invalidated object, the relationships are still available
					/// at this time. So KVC can be used as usual.

					if predicateMatching(snapshot) {
						let sectionName: ReactiveSetSectionName

						if let sectionNameKeyPath = sectionNameKeyPath {
							sectionName = ReactiveSetSectionName(converting: snapshot[sectionNameKeyPath])
						} else {
							sectionName = ReactiveSetSectionName()
						}

						if let index = sections.index(forName: sectionName) {
							if let objectIndex = sections[index].index(of: object,
							                                           using: objectSortDescriptors,
							                                           with: filteredCollection) {
								deletedObjects.orderedInsert(objectIndex, toCollectionAt: index)
							}
						}
					}
				}
			}
		}

		func computeSnapshot(for object: E) -> [String: AnyObject] {
			/// Assume only having one level deep relationship for the key paths.
			var values = object.committedValuesForKeys(nil)
			for (key, value) in object.changedValuesForCurrentEvent() {
				values[key] = value
			}

			for (keyPath, keyPathComponents) in sortKeyComponents {
				switch keyPathComponents.count {
				case 1:
					break

				case 2:
					let relatedObject = values[keyPathComponents[0]] as! NSManagedObject
					let changes = relatedObject.changedValuesForCurrentEvent()
					if let index = changes.indexForKey(keyPathComponents[1]) {
						values[keyPath] = changes[index].1
					} else {
						values[keyPath] = relatedObject.valueForKeyPath(keyPathComponents[1])
					}

				default:
					preconditionFailure("unexpected key path component count.")
				}
			}

			return values
		}

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

		func processUpdatedObjects(set: Set<NSManagedObject>, isRefreshing: Bool) {
			for object in set {
				guard let object = object as? E else {
					continue
				}

				/// `previousValuesForUpdatedQualifyingObjects` contains only remotely updated objects that were
				/// ONCE QUALIFIED for `self` at its pre-merge state.
				if isMergingRemoteChanges {
					/// Must compare the object pointer to obtain the index for any remotely refresh object,
					/// since no sufficient information is available for remotely deleted objects.

					var indexPath: (Int, Int)?

					for sectionIndex in sections.indices {
						/// Use binary search, but compare against the previous values dictionary.
						if let objectIndex = sections[sectionIndex].indexOf(object) {
							indexPath = (sectionIndex, objectIndex)
						}
					}

					guard let (foundSectionIndex, foundObjectIndex) = indexPath else {
						continue
					}

					if !predicateMatching(object) {
						/// The object no longer qualifies. Delete it from the ObjectSet.
						deletedObjects.orderedInsert(foundObjectIndex, toCollectionAt: foundSectionIndex)
						continue
					} else {
						/// The object still qualifies. Does it have any change affecting the sort order?
						let currentSectionName: ReactiveSetSectionName

						if let sectionNameKeyPath = sectionNameKeyPath {
							currentSectionName = sectionName(from: object)

							guard sections[foundSectionIndex].name == currentSectionName else {
								sectionChangedObjects.insert(object, intoSetAt: foundSectionIndex)
								continue
							}
						} else {
							currentSectionName = ReactiveSetSectionName()
						}

						guard let currentSectionIndex = sections.index(forName: currentSectionName) else {
							preconditionFailure("current section name is supposed to exist, but not found.")
						}

						let isLeftOrderChanged = foundObjectIndex > sections[foundSectionIndex].startIndex
							? objectSortDescriptors.compare(sections[foundSectionIndex][foundObjectIndex - 1],
							                                to: sections[foundSectionIndex][foundObjectIndex]) == .OrderedDescending
							: false

						let isRightOrderChanged = foundObjectIndex < sections[foundSectionIndex].endIndex - 1
							? objectSortDescriptors.compare(sections[foundSectionIndex][foundObjectIndex],
							                                to: sections[foundSectionIndex][foundObjectIndex + 1]) == .OrderedDescending
							: false

						guard !isLeftOrderChanged && !isRightOrderChanged else {
							sortOrderAffectingObjects.insert(object, intoSetAt: currentSectionIndex)
							continue
						}

						if !shouldExcludeUpdatedRows {
							updatedObjects.insert(object, intoSetAt: currentSectionIndex)
						}
					}
				} else if !isRefreshing {
					/// Based on the guarantee of infinite staleness, locally refreshed objects can be
					/// assumed to never change, thus ignored by the ObjectSet change tracking. In other
					/// words, if the object is refreshed but not captured by `remoteChanges`, it can be
					/// gracefully ignored.

					/// Ignore objects that do not match the predicate.
					if predicateMatching(object) {
						// check if object was in the objectset before.
						var previousValues = computeSnapshot(for: object)
						let currentSectionName: ReactiveSetSectionName
						let previousSectionName: ReactiveSetSectionName

						if let sectionNameKeyPath = sectionNameKeyPath {
							if let rawSectionName = previousValues[sectionNameKeyPath] {
								previousSectionName = ReactiveSetSectionName(converting: rawSectionName)
							} else {
								previousSectionName = ReactiveSetSectionName()
							}
							currentSectionName = sectionName(from: object)
						} else {
							currentSectionName = ReactiveSetSectionName()
							previousSectionName = ReactiveSetSectionName()
						}

						guard predicateMatching(previousValues) else {
							insertedObjects.insert(object, intoSetOfKey: currentSectionName)
							continue
						}

						guard previousSectionName == currentSectionName else {
							guard let previousSectionIndex = sections.index(forName: previousSectionName) else {
							      preconditionFailure("previous section name is supposed to exist, but not found.")
							}

							sectionChangedObjects.insert(object, intoSetAt: previousSectionIndex)
							continue
						}

						guard let currentSectionIndex = sections.index(forName: currentSectionName) else {
							preconditionFailure("current section name is supposed to exist, but not found.")
						}

						guard !sortOrderIsAffected(by: object, against: previousValues) else {
							sortOrderAffectingObjects.insert(object, intoSetAt: currentSectionIndex)
							continue
						}

						if !shouldExcludeUpdatedRows {
							updatedObjects.insert(object, intoSetAt: currentSectionIndex)
						}
					}
				}
			}
		}

		if let _insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
			for object in _insertedObjects {
				if let object = qualifyingObject(object) {
					let name = sectionName(from: object)
					insertedObjects.insert(object, intoSetOfKey: name)
				}
			}
		}

		if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
			processDeletedObjects(deletedObjects, isInvalidating: false)
		}

		if let invalidatedObjects = userInfo[NSInvalidatedObjectsKey] as? Set<NSManagedObject> {
			processDeletedObjects(invalidatedObjects, isInvalidating: true)
		}

		if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(updatedObjects, isRefreshing: false)
		}

		if let refreshedObjects = userInfo[NSRefreshedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(refreshedObjects, isRefreshing: true)
		}

		let insertedObjectsCount = insertedObjects.reduce(0) { $0 + $1.1.count }
		let deletedObjectsCount = deletedObjects.reduce(0) { $0 + $1.count }
		let sectionChangedObjectsCount = sectionChangedObjects.reduce(0) { $0 + $1.count }
		let updatedObjectsCount = updatedObjects.reduce(0) { $0 + $1.count }
		let sortOrderAffectingObjectsCount = sortOrderAffectingObjects.reduce(0) { $0 + $1.count }

		var inboundObjects = [ReactiveSetSectionName: Set<E>]()
		var inPlaceMovingObjects = sectionSnapshots.indices.map { _ in Set<E>() }
		var deletingIndexPaths = (0 ..< sectionSnapshots.count).map { _ in [Int]() }

		var originOfSectionChangedObjects = [E: NSIndexPath](minimumCapacity: sectionChangedObjectsCount)
		var originOfMovedObjects = [E: NSIndexPath](minimumCapacity: sortOrderAffectingObjectsCount)

		var indexPathsOfInsertedRows = [NSIndexPath]()
		var indexPathsOfUpdatedRows = [NSIndexPath]()
		var indexPathsOfMovedRows = [(NSIndexPath, NSIndexPath)]()

		let indiceOfDeletedSections = NSMutableIndexSet()
		let indiceOfInsertedSections = NSMutableIndexSet()

		indexPathsOfInsertedRows.reserveCapacity(insertedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(sectionChangedObjectsCount + sortOrderAffectingObjectsCount)

		/// MARK: Handle deletions.

		var indexPathsOfDeletedRows = deletedObjects.enumerate().flatMap { (sectionIndex, indice) in
			return indice.map { objectIndex -> NSIndexPath in
				deletingIndexPaths.orderedInsert(objectIndex, toCollectionAt: sectionIndex, ascending: false)
				return NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
			}
		}

		for (previousSectionIndex, objects) in sectionChangedObjects.enumerate() {
			for object in objects {
				guard let objectIndex = sectionSnapshots[previousSectionIndex].indexOf(object) else {
					assertionFailure("Object `\(object)` should be in section \(previousSectionIndex), but it cannot be found.")
					continue
				}

				deletingIndexPaths.orderedInsert(objectIndex, toCollectionAt: previousSectionIndex, ascending: false)

				let indexPath = NSIndexPath(forRow: objectIndex, inSection: previousSectionIndex)
				originOfSectionChangedObjects[object] = indexPath

				let newSectionName = sectionName(from: object)
				inboundObjects.insert(object, intoSetOfKey: newSectionName)
			}
		}

		for (previousSectionIndex, objects) in sortOrderAffectingObjects.enumerate() {
			for object in objects {
				guard let objectIndex = sectionSnapshots[previousSectionIndex].indexOf(object) else {
					assertionFailure("Object `\(object)` should be in section \(previousSectionIndex), but it cannot be found.")
					continue
				}

				deletingIndexPaths.orderedInsert(objectIndex, toCollectionAt: previousSectionIndex, ascending: false)

				let indexPath = NSIndexPath(forRow: objectIndex, inSection: previousSectionIndex)
				originOfMovedObjects[object] = indexPath

				inPlaceMovingObjects.insert(object, intoSetAt: previousSectionIndex)
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
				indiceOfDeletedSections.addIndex(index)
			}
		}

		/// MARK: Handle insertions.

		func insert(objects: Set<E>, intoSectionFor name: ReactiveSetSectionName) {
			if let sectionIndex = sections.index(forName: name) {
				for object in objects {
					sections[sectionIndex].insert(object, using: objectSortDescriptors)
				}
			} else {
				let index = sections.insert(ObjectSetSection(name: name,
					array: ContiguousArray(objects)),
				                            name: name,
				                            ordering: sectionNameOrdering)

				indiceOfInsertedSections.addIndex(index)
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
			let previousSectionIndex = sectionSnapshots.index(forName: sectionName)

			if let previousSectionIndex = previousSectionIndex {
				for object in inPlaceMovingObjects[previousSectionIndex] {
					sections[sectionIndex].insert(object, using: objectSortDescriptors)
				}
			}

			let insertedObjects = insertedObjects[sectionName] ?? []
			let inboundObjects = inboundObjects[sectionName] ?? []

			for (objectIndex, object) in sections[sectionIndex].enumerate() {
				if !shouldExcludeUpdatedRows, let oldSectionIndex = previousSectionIndex where updatedObjects[oldSectionIndex].contains(object) {
					let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
					indexPathsOfUpdatedRows.append(indexPath)
					continue
				}

				if insertedObjects.contains(object) {
					let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
					indexPathsOfInsertedRows.append(indexPath)
					continue
				}

				if let indexPath = originOfMovedObjects[object] {
					let from = indexPath
					let to = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
					indexPathsOfMovedRows.append((from, to))

					continue
				}

				if inboundObjects.contains(object) {
					let origin = originOfSectionChangedObjects[object]!

					if indiceOfDeletedSections.contains(origin.section) {
						/// The originated section no longer exists, treat it as an inserted row.
						let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfInsertedRows.append(indexPath)
						continue
					}

					if indiceOfInsertedSections.contains(sectionIndex) {
						/// The target section is newly created.
						continue
					}

					let to = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
					indexPathsOfMovedRows.append((origin, to))
					continue
				}
			}
		}

		let resultSetChanges = ReactiveSetChanges(indexPathsOfDeletedRows: indexPathsOfDeletedRows,
		                                          indexPathsOfInsertedRows: indexPathsOfInsertedRows,
		                                          indexPathsOfMovedRows: indexPathsOfMovedRows,
		                                          indexPathsOfUpdatedRows: indexPathsOfUpdatedRows,
		                                          indiceOfInsertedSections: indiceOfInsertedSections,
		                                          indiceOfDeletedSections: indiceOfDeletedSections)

		eventObserver.sendNext(.Updated(resultSetChanges))
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
		return AnyReactiveSetIterator {
			if index < self.endIndex {
				defer { index = index.successor() }
				return self[index]
			} else {
				return nil
			}
		}
	}

	// CollectionType

	public subscript(bounds: Range<Int>) -> ArraySlice<ObjectSetSection<E>> {
		return sections[bounds]
	}
}

private class RemoteChanges<E: NSManagedObject> {
	var updatedUnqualifyingObjects: Set<NSManagedObject>
	var previousValuesForUpdatedQualifyingObjects: [E: [String: AnyObject]]?
	var previousValuesForDeletedQualifyingObjects: [E: [String: AnyObject]]?

	init(updatedUnqualifyingObjects: Set<NSManagedObject>, previousValuesForUpdatedQualifyingObjects: [E: [String: AnyObject]]?, previousValuesForDeletedQualifyingObjects: [E: [String: AnyObject]]?) {
		self.previousValuesForDeletedQualifyingObjects = previousValuesForDeletedQualifyingObjects
		self.previousValuesForUpdatedQualifyingObjects = previousValuesForUpdatedQualifyingObjects
		self.updatedUnqualifyingObjects = updatedUnqualifyingObjects
	}
}

public struct ObjectSetSection<E: NSManagedObject> {
	public let name: ReactiveSetSectionName
	private var storage: ContiguousArray<E>

	public init(name: ReactiveSetSectionName, array: ContiguousArray<E>?) {
		self.name = name
		self.storage = array ?? []
	}
}

extension ObjectSetSection: ReactiveSetSection {
	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public subscript(index: Int) -> E {
		get { return storage[index] }
		set { storage[index] = newValue }
	}
}

extension ObjectSetSection: RangeReplaceableCollectionType {
	public init() {
		_unimplementedMethod()
	}

	public mutating func replaceRange<C : CollectionType where C.Generator.Element == E>(subRange: Range<Int>, with newElements: C) {
		storage.replaceRange(subRange, with: newElements)
	}
}

extension ObjectSetSection: MutableCollectionType {}