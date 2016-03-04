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
final public class ObjectSet<E: Object>: Base {
	public let fetchRequest: NSFetchRequest
	public let entity: NSEntityDescription

	public let sectionNameKeyPath: String?
	public let _sectionNameKeyPath: [String]?
	public let defaultSectionName: String

	public let sectionNameOrdering: NSComparisonResult
	public let objectSortDescriptors: [NSSortDescriptor]

	// An ObjectSet retains the managed object context.
	private(set) public weak var context: ObjectContext!

	private var eventObserver: Observer<ReactiveSetEvent, NoError>?

	private(set) public lazy var eventProducer: SignalProducer<ReactiveSetEvent, NoError> = { [unowned self] in
		let (producer, observer) = SignalProducer<ReactiveSetEvent, NoError>.buffer(0)
		self.eventObserver = observer
		return producer
		}()

	private var sections: [ObjectSetSection<E>] = []

	private(set) public var isFetched: Bool = false

	public init(fetchRequest: NSFetchRequest, context: ObjectContext, sectionNameKeyPath: String? = nil, defaultSectionName: String = "") {
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
			                                                 selector: "mergeChangesFrom:",
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
				array: fetchedObjects)]

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
				let section = ObjectSetSection(name: name, array: Array(fetchedObjects[range]))
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
		if object.entity.name == entity.name {
			if fetchRequest.predicate?.evaluateWithObject(object) ?? true {
				return object as? E
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
					externalChanges.insertedObjects.insert(object, inSetForKey: name)
					externalChanges.insertedObjectsCount = externalChanges.insertedObjectsCount + 1
				}
			}
		}

		if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
			for object in deletedObjects {
				if let object = isInclusiveOf(object) {
					let name = sectionName(from: object)
					externalChanges.deletedObjects.insert(object, inSetForKey: name)
					externalChanges.deletedObjectsCount = externalChanges.deletedObjectsCount + 1
				}
			}
		}

		if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
			for object in updatedObjects {
				if let object = isInclusiveOf(object) {
					let name: ReactiveSetSectionName

					if sectionNameKeyPath != nil {
						let __object: E = _sectionNameKeyPath!.count > 1
							? object.valueForKeyPath(_sectionNameKeyPath!.first!) as! E
							: object

						name = sectionName(from: object)

						let changedDict = __object.changedValuesForCurrentEvent()
						if changedDict.keys.contains(_sectionNameKeyPath!.last!) {
							let oldSectionName = ReactiveSetSectionName(changedDict[_sectionNameKeyPath!.last!] as? String)
							if oldSectionName != name {
								externalChanges.movedObjects.insert(object, inSetForKey: oldSectionName)
								externalChanges.movedObjectsCount = externalChanges.movedObjectsCount + 1

								continue
							}
						}
					} else {
						name = ReactiveSetSectionName(nil)
					}

					externalChanges.updatedObjects.insert(object, inSetForKey: name)
					externalChanges.updatedObjectsCount = externalChanges.updatedObjectsCount + 1
				}
			}
		}

		guard externalChanges.hasChanges else {
			return
		}

		let oldSections = sections
		var updatedSections = sections

		var inboundObjects = [ReactiveSetSectionName: ContiguousArray<E>](minimumCapacity: externalChanges.movedObjects.count)
		var originsOfMoved = ContiguousArray<NSIndexPath>()
		originsOfMoved.reserveCapacity(externalChanges.movedObjectsCount)

		var indexPathsOfInsertedRows = [NSIndexPath]()
		var indexPathsOfDeletedRows = [NSIndexPath]()
		var indexPathsOfUpdatedRows = [NSIndexPath]()
		var indexPathsOfMovedRows = [(NSIndexPath, NSIndexPath)]()

		let indiceOfDeletedSections = NSMutableIndexSet()
		let indiceOfInsertedSections = NSMutableIndexSet()

		indexPathsOfInsertedRows.reserveCapacity(externalChanges.insertedObjectsCount)
		indexPathsOfDeletedRows.reserveCapacity(externalChanges.deletedObjectsCount)
		indexPathsOfUpdatedRows.reserveCapacity(externalChanges.updatedObjectsCount)
		indexPathsOfMovedRows.reserveCapacity(originsOfMoved.capacity)

		for (sectionName, objects) in externalChanges.deletedObjects {
			guard let sectionIndex = oldSections.index(forName: sectionName) else {
				assertionFailure("Section `\(sectionName)` should be in the result set, but it cannot be found.")
				continue
			}

			for object in objects {
				guard let rowIndex = oldSections[sectionIndex].indexOf(object) else {
					assertionFailure("Object `\(object)` should be in the section `\(sectionName)`, but it cannot be found.")
					continue
				}

				let indexPath = NSIndexPath(forRow: rowIndex, inSection: sectionIndex)
				indexPathsOfDeletedRows.append(indexPath)
			}
		}

		for (oldSectionName, objects) in externalChanges.movedObjects {
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
				originsOfMoved.append(indexPath)
			}
		}

		for indexPath in originsOfMoved {
			let object = oldSections[indexPath.section][indexPath.row]
			let name = sectionName(from: object)
			inboundObjects.insert(object, inSetForKey: name)
		}

		var pendingDelete = ContiguousArray<NSIndexPath>()
		pendingDelete.appendContentsOf(originsOfMoved)
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
				updatedSections[sectionIndex].appendContentsOf(objects)
			} else {
				let index = updatedSections.insertSection(sectionName,
				                                          ordering: sectionNameOrdering,
				                                          section: ObjectSetSection(name: sectionName,
																										array: Array(objects)))

				indiceOfInsertedSections.addIndex(index)
			}
		}

		for (sectionName, objects) in inboundObjects {
			if let sectionIndex = updatedSections.index(forName: sectionName) {
				updatedSections[sectionIndex].appendContentsOf(objects)
			} else {
				let index = updatedSections.insertSection(sectionName,
				                                          ordering: sectionNameOrdering,
				                                          section: ObjectSetSection(name: sectionName,
																										array: Array(objects)))

				indiceOfInsertedSections.addIndex(index)
			}
		}

		for sectionIndex in updatedSections.indices {
			let sectionName = updatedSections[sectionIndex].name
			let oldSectionIndex = oldSections.index(forName: sectionName)

			updatedSections[sectionIndex]._sortInPlace(objectSortDescriptors)

			for (objectIndex, object) in updatedSections[sectionIndex].enumerate() {
				if let oldSectionIndex = oldSectionIndex {
					if objectIndex < oldSections[oldSectionIndex].count && object == oldSections[oldSectionIndex][objectIndex] {
						if let isUpdated = externalChanges.updatedObjects[sectionName]?.contains(object) where isUpdated {
							let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
							indexPathsOfUpdatedRows.append(indexPath)
						}
						continue
					}
				}

				if let isInserted = externalChanges.insertedObjects[sectionName]?.contains(object) where isInserted {
					indexPathsOfInsertedRows.append(NSIndexPath(forRow: objectIndex, inSection: sectionIndex))
					continue
				}

				if let inboundIndex = inboundObjects[sectionName]?.indexOf(object) {
					if indiceOfDeletedSections.contains(originsOfMoved[inboundIndex].section) {
						let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfInsertedRows.append(indexPath)
					} else if indiceOfInsertedSections.contains(sectionIndex) {
						let indexPath = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfDeletedRows.append(originsOfMoved[inboundIndex])
						indexPathsOfInsertedRows.append(indexPath)
					} else {
						let from = originsOfMoved[inboundIndex]
						let to = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
						indexPathsOfMovedRows.append((from, to))
					}
					continue
				}

				if let oldSectionIndex = oldSectionIndex, oldIndex = oldSections[oldSectionIndex].indexOf(object) {
					let from = NSIndexPath(forRow: oldIndex, inSection: oldSectionIndex)
					let to = NSIndexPath(forRow: objectIndex, inSection: sectionIndex)
					indexPathsOfMovedRows.append((from, to))
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

private struct ExternalChanges<E: Object> {
	var insertedObjects: [ReactiveSetSectionName: Set<E>] = [:]
	var deletedObjects: [ReactiveSetSectionName: Set<E>] = [:]
	var movedObjects: [ReactiveSetSectionName: Set<E>] = [:]
	var updatedObjects: [ReactiveSetSectionName: Set<E>] = [:]

	var insertedObjectsCount: Int = 0
	var deletedObjectsCount: Int = 0
	var movedObjectsCount: Int = 0
	var updatedObjectsCount: Int = 0

	var hasChanges: Bool {
		return insertedObjectsCount > 0 || deletedObjectsCount > 0 || movedObjectsCount > 0 || updatedObjectsCount > 0
	}
}

public struct ObjectSetSection<E: Object> {
	public let name: ReactiveSetSectionName
	private var storage: [E]

	public init(name: ReactiveSetSectionName, array: [E]?) {
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

	public func generate() -> IndexingGenerator<Array<E>> {
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