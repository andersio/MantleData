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

///
/// A controler that manages results of a Core Data fetch request.
/// You must use this controller only on the same thread as the associated context.
///
final public class ObjectSet<E: NSManagedObject>: Base {
	public let fetchRequest: NSFetchRequest
	public let entity: NSEntityDescription

	public let sectionNameKeyPath: String?
	public let _sectionNameKeyPath: [String]?
	public let defaultSectionName: String

	public let sectionNameOrdering: NSComparisonResult
	public let objectSortDescriptors: [NSSortDescriptor]

	// An ObjectSet retains the managed object context.
	private(set) public weak var context: NSManagedObjectContext!

	private var eventObserver: Observer<ReactiveSetEvent, NoError>?

	private(set) public lazy var eventProducer: SignalProducer<ReactiveSetEvent, NoError> = { [unowned self] in
		let (producer, observer) = SignalProducer<ReactiveSetEvent, NoError>.buffer(0)
		self.eventObserver = observer
		return producer
		}()

	private var sections: [ObjectSetSection<E>] = []

	private(set) public var isFetched: Bool = false

	public init(fetchRequest: NSFetchRequest, context: NSManagedObjectContext, sectionNameKeyPath: String? = nil, defaultSectionName: String = "") {
		self.context = context
		self.fetchRequest = fetchRequest
		self.entity = fetchRequest.entity!

		self.defaultSectionName = defaultSectionName
		self.sectionNameKeyPath = sectionNameKeyPath
		self._sectionNameKeyPath = sectionNameKeyPath?.componentsSeparatedByString(".")

		precondition(fetchRequest.sortDescriptors != nil, "ObjectSet requires sort descriptors to work.")

		if let keyPath = sectionNameKeyPath {
			precondition(fetchRequest.sortDescriptors!.count >= 2, "Unsufficient number of sort descriptors.")
			self.fetchRequest.relationshipKeyPathsForPrefetching = [keyPath]
			self.sectionNameOrdering = fetchRequest.sortDescriptors!.first!.ascending ? .OrderedAscending : .OrderedDescending
			self.objectSortDescriptors = Array(fetchRequest.sortDescriptors!.dropFirst())
		} else {
			self.sectionNameOrdering = .OrderedSame
			self.objectSortDescriptors = fetchRequest.sortDescriptors ?? []
		}

		super.init()

		precondition(self._sectionNameKeyPath?.count ?? 0 <= 2, "ObjectSet supports only direct relationship on the key path for section name.")
		self.fetchRequest.resultType = .ManagedObjectResultType
	}

	public func fetch() throws {
		if isFetched {
			return
		}

		func completionBlock(result: NSAsynchronousFetchResult) {
			self.sectionize(using: result.finalResult as? [E] ?? [])
			eventObserver?.sendNext(.Reloaded)

			NSNotificationCenter.defaultCenter().addObserver(self,
			                                                 selector: #selector(ObjectSet.mergeChangesFrom(_:)),
			                                                 name: NSManagedObjectContextObjectsDidChangeNotification,
			                                                 object: self.context)

			self.context.willDeinitProducer
				.takeUntil(self.willDeinitProducer)
				.startWithCompleted { [weak self] in
					if let self_ = self {
						NSNotificationCenter.defaultCenter().removeObserver(self_,
							name: NSManagedObjectContextObjectsDidChangeNotification,
							object: self_.context)
					}
			}
		}

		context.performBlock {
			let asyncRequest = NSAsynchronousFetchRequest(fetchRequest: self.fetchRequest, completionBlock: completionBlock)

			do {
				try self.context.executeRequest(asyncRequest)
			} catch let error as NSError {
				fatalError("\(error.description)")
			}
		}
	}

	private func sectionize(using fetchedObjects: [E]) {
		guard let keyPath = sectionNameKeyPath else {
			sections = [ObjectSetSection(name: ReactiveSetSectionName(nil),
				array: ContiguousArray(fetchedObjects))]

			return
		}

		if !fetchedObjects.isEmpty {
			var ranges: [(range: Range<Int>, name: ReactiveSetSectionName)] = []

			// Objects are sorted wrt to sections already.
			for position in fetchedObjects.startIndex ..< fetchedObjects.endIndex {
				let sectionName: ReactiveSetSectionName

				switch fetchedObjects[position].valueForKeyPath(keyPath) {
				case let name as String:
					sectionName = ReactiveSetSectionName(name)
				case let name as NSNumber:
					sectionName = ReactiveSetSectionName(name.stringValue)
				default:
					sectionName = ReactiveSetSectionName(nil)
				}

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

		isFetched = true
	}

	private func sectionName(from object: E) -> ReactiveSetSectionName {
		if let keyPath = self.sectionNameKeyPath {
			switch object.valueForKeyPath(keyPath) {
			case let name as String:
				return ReactiveSetSectionName(name)
			case let name as NSNumber:
				return ReactiveSetSectionName(name.stringValue)
			default:
				return ReactiveSetSectionName(nil)
			}
		}
		return ReactiveSetSectionName(nil)
	}

	private func isInclusiveOf(object: NSManagedObject) -> E? {
		if let object = object as? E {
			if fetchRequest.predicate?.evaluateWithObject(object) ?? true {
				return object
			}
		}
		return nil
	}

	private func hasObject(object: E) -> (sectionName: ReactiveSetSectionName, index: Int)? {
		for section in sections {
			if let index = section.indexOf(object) {
				return (sectionName: section.name, index: index)
			}
		}

		return nil
	}

	/// Merge changes since last posting of NSManagedContextObjectsDidChangeNotification.
	@objc private func mergeChangesFrom(notification: NSNotification) {
		guard let userInfo = notification.userInfo else {
			return
		}

		var externalChanges = ExternalChanges<E>()

		if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
			for object in insertedObjects {
				if let object = isInclusiveOf(object) {
					let name = sectionName(from: object)
					externalChanges.insertedObjects.insert(object, intoSetOfKey: name)
					externalChanges.insertedObjectsCount = externalChanges.insertedObjectsCount + 1
				}
			}
		}

		if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
			for object in deletedObjects {
				guard let object = object as? E else {
					continue
				}

				if let (sectionName, index) = hasObject(object) {
					externalChanges.deletedObjects.insert(index, intoSetOfKey: sectionName)
					externalChanges.deletedObjectsCount = externalChanges.deletedObjectsCount + 1
				}
			}
		}

		func processUpdatedObjects(set: Set<NSManagedObject>, isRefreshing: Bool) {
			for object in set {
				if let object = isInclusiveOf(object) {
					let name: ReactiveSetSectionName

					if sectionNameKeyPath != nil {
						let __object: NSManagedObject = _sectionNameKeyPath!.count > 1
							? object.valueForKeyPath(_sectionNameKeyPath!.first!) as! NSManagedObject
							: object

						name = sectionName(from: object)

						let changedDict = __object.changedValuesForCurrentEvent()
						if changedDict.keys.contains(_sectionNameKeyPath!.last!) {
							let oldSectionName = ReactiveSetSectionName(changedDict[_sectionNameKeyPath!.last!] as? String)
							if oldSectionName != name {
								externalChanges.sectionChangedObjects.insert(object, intoSetOfKey: oldSectionName)
								externalChanges.sectionChangedObjectsCount = externalChanges.sectionChangedObjectsCount + 1

								continue
							}
						}
					} else {
						name = ReactiveSetSectionName(nil)
					}

					externalChanges.updatedObjects.insert(object, intoSetOfKey: name)
					externalChanges.updatedObjectsCount = externalChanges.updatedObjectsCount + 1
				}
			}
		}

		if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(updatedObjects, isRefreshing: false)
		}

		if let refreshedObjects = userInfo[NSRefreshedObjectsKey] as? Set<NSManagedObject> {
			processUpdatedObjects(refreshedObjects, isRefreshing: true)
		}

		guard externalChanges.hasChanges else {
			return
		}

		let oldSections = sections
		var updatedSections = sections

		var inboundObjects = [ReactiveSetSectionName: Set<E>]()
		var originOfSectionChangedObjects = [E: NSIndexPath](minimumCapacity: externalChanges.sectionChangedObjectsCount)

		var indexPathsOfInsertedRows = [NSIndexPath]()
		var indexPathsOfDeletedRows = [NSIndexPath]()
		var indexPathsOfUpdatedRows = [NSIndexPath]()
		var indexPathsOfMovedRows = [(NSIndexPath, NSIndexPath)]()

		let indiceOfDeletedSections = NSMutableIndexSet()
		let indiceOfInsertedSections = NSMutableIndexSet()

		indexPathsOfInsertedRows.reserveCapacity(externalChanges.insertedObjectsCount)
		indexPathsOfDeletedRows.reserveCapacity(externalChanges.deletedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(externalChanges.updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(externalChanges.sectionChangedObjectsCount)

		for (sectionName, objectIndice) in externalChanges.deletedObjects {
			guard let sectionIndex = oldSections.index(forName: sectionName) else {
				assertionFailure("Section `\(sectionName)` should be in the result set, but it cannot be found.")
				continue
			}

			for objectIndex in objectIndice {
				let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
				indexPathsOfDeletedRows.append(indexPath)
			}
		}

		for (oldSectionName, objects) in externalChanges.sectionChangedObjects {
			guard let oldSectionIndex = oldSections.index(forName: oldSectionName) else {
				assertionFailure("Section `\(oldSectionName)` should be in the result set, but cannot be found.")
				continue
			}

			for object in objects {
				guard let rowIndex = oldSections[oldSectionIndex].indexOf(object) else {
					assertionFailure("Object `\(object)` should be in the section `\(oldSectionName)`, but it cannot be found.")
					continue
				}

				let indexPath = NSIndexPath(forRow: rowIndex, inSection: oldSectionIndex)
				originOfSectionChangedObjects[object] = indexPath

				let newSectionName = sectionName(from: object)
				inboundObjects.insert(object, intoSetOfKey: newSectionName)
			}
		}

		var pendingDelete = ContiguousArray<NSIndexPath>()
		pendingDelete.appendContentsOf(originOfSectionChangedObjects.values)
		pendingDelete.appendContentsOf(indexPathsOfDeletedRows)
		pendingDelete.sortInPlace { $0.row > $1.row }

		for indexPath in pendingDelete {
			updatedSections[indexPath.section].removeAtIndex(indexPath.row)
		}

		for sectionIndex in updatedSections.indices {
			if updatedSections[sectionIndex].count == 0 {
				indiceOfDeletedSections.addIndex(sectionIndex)
			}
		}

		for sectionIndex in indiceOfDeletedSections.reverse() {
			updatedSections.removeAtIndex(sectionIndex)
		}

		for (sectionName, objects) in externalChanges.insertedObjects {
			if let sectionIndex = updatedSections.index(forName: sectionName) {
				for object in objects {
					updatedSections[sectionIndex].insert(object, using: objectSortDescriptors)
				}
			} else {
				let index = updatedSections.insert(ObjectSetSection(name: sectionName,
																														array: ContiguousArray(objects)),
				                                   name: sectionName,
				                                   ordering: sectionNameOrdering)

				indiceOfInsertedSections.addIndex(index)
			}
		}

		for (sectionName, objects) in inboundObjects {
			if let sectionIndex = updatedSections.index(forName: sectionName) {
				for object in objects {
					updatedSections[sectionIndex].insert(object, using: objectSortDescriptors)
				}
			} else {
				let index = updatedSections.insert(ObjectSetSection(name: sectionName,
																														array: ContiguousArray(objects)),
				                                   name: sectionName,
				                                   ordering: sectionNameOrdering)

				indiceOfInsertedSections.addIndex(index)
			}
		}

		for sectionIndex in updatedSections.indices {
			let sectionName = updatedSections[sectionIndex].name
			let oldSectionIndex = oldSections.index(forName: sectionName)

			updatedSections[sectionIndex].sort(with: objectSortDescriptors)

			for (objectIndex, object) in updatedSections[sectionIndex].enumerate() {
				if let oldSectionIndex = oldSectionIndex {
					if objectIndex < oldSections[oldSectionIndex].count && object == oldSections[oldSectionIndex][objectIndex] {
						if let isUpdated = externalChanges.updatedObjects[sectionName]?.contains(object) where isUpdated {
							let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
							indexPathsOfUpdatedRows.append(indexPath)
						}
						continue
					}

					if let oldIndex = oldSections[oldSectionIndex].indexOf(object) {
						let from = NSIndexPath(forRow: oldIndex, inSection: sectionIndex)
						let to = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfMovedRows.append((from, to))
						continue
					}
				}

				if let isInserted = externalChanges.insertedObjects[sectionName]?.contains(object) where isInserted {
					indexPathsOfInsertedRows.append(NSIndexPath(forRow: objectIndex, inSection: sectionIndex))
					continue
				}

				if let inboundIndex = inboundObjects[sectionName]?.contains(object) {
					if indiceOfDeletedSections.contains(originOfSectionChangedObjects[object]!.section) {
						let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfInsertedRows.append(indexPath)
					} else if indiceOfInsertedSections.contains(sectionIndex) {
						let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfDeletedRows.append(originOfSectionChangedObjects[object]!)
						indexPathsOfInsertedRows.append(indexPath)
					} else {
						let from = originOfSectionChangedObjects[object]!
						let to = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfMovedRows.append((from, to))
					}
					continue
				}
			}
		}

		sections = updatedSections

		let resultSetChanges = ReactiveSetChanges(indexPathsOfDeletedRows: indexPathsOfDeletedRows,
		                                          indexPathsOfInsertedRows: indexPathsOfInsertedRows,
		                                          indexPathsOfMovedRows: indexPathsOfMovedRows,
		                                          indexPathsOfUpdatedRows: indexPathsOfUpdatedRows,
		                                          indiceOfInsertedSections: indiceOfInsertedSections,
		                                          indiceOfDeletedSections: indiceOfDeletedSections)

		eventObserver?.sendNext(.Updated(resultSetChanges))
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

private struct ExternalChanges<E: NSManagedObject> {
	var insertedObjects: [ReactiveSetSectionName: Set<E>] = [:]
	var deletedObjects: [ReactiveSetSectionName: Set<Int>] = [:]
	var sectionChangedObjects: [ReactiveSetSectionName: Set<E>] = [:]
	var updatedObjects: [ReactiveSetSectionName: Set<E>] = [:]

	var insertedObjectsCount: Int = 0
	var deletedObjectsCount: Int = 0
	var sectionChangedObjectsCount: Int = 0
	var updatedObjectsCount: Int = 0

	var hasChanges: Bool {
		return insertedObjectsCount > 0 || deletedObjectsCount > 0 || sectionChangedObjectsCount > 0 || updatedObjectsCount > 0
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
	// Indexable

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

	// SequenceType

	public func generate() -> IndexingGenerator<ContiguousArray<E>> {
		return IndexingGenerator(storage)
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