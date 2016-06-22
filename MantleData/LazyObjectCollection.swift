//
//  LazyObjectCollection.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveCocoa

public enum SortingOrder {
	case ascending
	case descending

	private var isAscending: Bool {
		if case .ascending = self {
			return true
		}

		return false
	}
}

/// **LazyObjectCollection**
///
/// A lazily initialized collection of Core Data entity objects,
/// bounded by the supplied constraints.
///
/// The collection is a fault which performs a fetch only when you use any
/// standard collection methods, e.g. a subscript getter. Therefore, you may
/// gracefully use this collection as an `ObjectSet` builder without faulting
/// in any result.
///
/// - Note: This is not a reactive collection like `ObjectSet` or
///					`NSFetchedResultsController`.
public class LazyObjectCollection<Entity: NSManagedObject> {
  private let context: NSManagedObjectContext
  private let fetchRequest: NSFetchRequest
	private var hasGroupByKeyPath = false

	public private(set) var isFault = true
	private var storage: [Entity]?

	public var copy: LazyObjectCollection {
		return LazyObjectCollection(using: fetchRequest.copy() as! NSFetchRequest,
		                            in: context)
	}

	public init(in context: NSManagedObjectContext) {
		guard let entityDescription = NSEntityDescription.entityForName(String(Entity),
		                                                                inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(String(Entity))`.")
		}

		let fetchRequest = NSFetchRequest()
		fetchRequest.entity = entityDescription

		self.context = context
		self.fetchRequest = fetchRequest
	}

	public func fetchInBackground() -> SignalProducer<LazyObjectCollection, NSError> {
		return SignalProducer { observer, disposable in
			if self.isFault {
				self.fetchRequest.resultType = .ManagedObjectResultType

				let asyncFetchRequest = NSAsynchronousFetchRequest(fetchRequest: self.fetchRequest) { fetchResult in
					self.storage = fetchResult.finalResult as? [Entity] ?? []
					self.isFault = false
					observer.sendCompleted(with: self)
				}

				do {
					_ = try self.context.executeRequest(asyncFetchRequest)
				} catch let error as NSError {
					observer.sendFailed(error)
				}
			} else {
				observer.sendInterrupted()
			}
		}
	}

	private init(using fetchRequest: NSFetchRequest, in context: NSManagedObjectContext) {
		self.context = context
		self.fetchRequest = fetchRequest
	}

	private func willAccessStorage() {
		if isFault {
			fetchRequest.resultType = .ManagedObjectResultType
			storage = try! context.executeFetchRequest(fetchRequest) as! [Entity]
			isFault = false
		}
	}

	public func refresh() {
		storage = nil
		isFault = true
	}
}

/// Collection conformance

extension LazyObjectCollection: CollectionType {
	public var startIndex: Int {
		willAccessStorage()
		return storage!.startIndex
	}

	public var endIndex: Int {
		willAccessStorage()
		return storage!.endIndex
	}

	public subscript(position: Int) -> Entity {
		willAccessStorage()
		return storage![position]
	}
}

/// Constraints

extension LazyObjectCollection {
	public func filter(using predicate: NSPredicate?) -> LazyObjectCollection {
		fetchRequest.predicate = predicate
		return self
	}

	public func filter(by expression: String, _ arguments: AnyObject...) -> LazyObjectCollection {
		filter(by: expression, with: arguments)
		return self
	}

	public func filter(by expression: String, with argumentArray: [AnyObject]) -> LazyObjectCollection {
		fetchRequest.predicate = NSPredicate(format: expression, argumentArray: argumentArray)
		return self
	}

  /// MARK: Ordering operators
  
  public func sort(byKeyPath path: String, order: SortingOrder = .ascending) -> LazyObjectCollection {
		if fetchRequest.sortDescriptors == nil {
			fetchRequest.sortDescriptors = []
		}

		let sortDescriptor = NSSortDescriptor(key: path, ascending: order.isAscending)
    fetchRequest.sortDescriptors!.append(sortDescriptor)

		return self
  }
  
  public func group(byKeyPath path: String, order: SortingOrder = .ascending) -> LazyObjectCollection {
		assert(!hasGroupByKeyPath, "You can only group by one key path.")
		hasGroupByKeyPath = true

		if fetchRequest.sortDescriptors == nil {
			fetchRequest.sortDescriptors = []
		}

		let sortDescriptor = NSSortDescriptor(key: path, ascending: order.isAscending)
		fetchRequest.sortDescriptors!.insert(sortDescriptor, atIndex: 0)

		return self
	}
}

/// MARK: Factories

extension LazyObjectCollection {
	public func makeObjectSet(prefetching policy: ObjectSetPrefetchingPolicy = .none) -> ObjectSet<Entity> {
		return ObjectSet(for: fetchRequest,
		                 in: context,
		                 prefetchingPolicy: policy,
		                 sectionNameKeyPath: hasGroupByKeyPath ? fetchRequest.sortDescriptors!.first!.key! : nil)
	}

	#if os(iOS)
	public func makeController() -> NSFetchedResultsController {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		return NSFetchedResultsController(fetchRequest: fetchRequest,
		                                  managedObjectContext: context,
		                                  sectionNameKeyPath: hasGroupByKeyPath ? fetchRequest.sortDescriptors!.first!.key! : nil,
		                                  cacheName: nil)
	}
	#endif
}

/// MARK: Others

extension LazyObjectCollection {
	private func fetchingDictionary(using fetchRequest: NSFetchRequest) throws -> [[String: AnyObject]] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		fetchRequest.resultType = .DictionaryResultType
		return try context.executeFetchRequest(fetchRequest) as! [[String: AnyObject]]
	}

	public var resultingIDs: [NSManagedObjectID] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		fetchRequest.resultType = .ManagedObjectIDResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return try! context.executeFetchRequest(fetchRequest) as! [NSManagedObjectID]
	}

	public var resultingCount: Int {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		fetchRequest.resultType = .CountResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return context.countForFetchRequest(fetchRequest, error: nil)
	}

	/// Aggregate Functions

	public func count(ofKeyPath path: String) -> Int {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: path)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.propertiesToFetch = [count]

		let results = try! fetchingDictionary(using: fetchRequest)
		return Int(cocoaValue: results.first!["count"])
	}

	public func count(ofKeyPath path: String, groupByKeyPath groupByPath: String) -> [Int] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: path)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [count, groupByPath]
		fetchRequest.propertiesToGroupBy = [groupByPath]

		let results = try! fetchingDictionary(using: fetchRequest)

		return results.map {
			Int(cocoaValue: $0["count"])
		}
	}

	public func sum(ofKeyPath path: String) throws -> Int {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		let sum = NSExpressionDescription()
		sum.name = "sum"
		sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: path)])
		sum.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [sum]

		let results = try fetchingDictionary(using: fetchRequest)

		return Int(cocoaValue: results.first!["sum"])
	}

	public func sum(ofKeyPath path: String, groupByKeyPath groupByPath: String) throws -> [Int] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		let sum = NSExpressionDescription()
		sum.name = "sum"
		sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: path)])
		sum.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [sum, groupByPath]
		fetchRequest.propertiesToGroupBy = [groupByPath]

		let results = try fetchingDictionary(using: fetchRequest)

		return results.map {
			Int(cocoaValue: $0["sum"])
		}
	}

	/// MARK: Batch Update Operators

	public func update<Value: CocoaBridgeable>(newValue value: Value, forKeyPath path: String) throws {
		try update(from: NSExpression(forConstantValue: value.cocoaValue), forKeyPath: path)
	}

	public func update(from expression: NSExpression, forKeyPath path: String) throws {
		try update([path: expression])
	}

	public func update(dictionary: [String: NSExpression]) throws {
		guard let entityDescription = NSEntityDescription.entityForName(String(Entity), inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(String(Entity))`.")
		}

		let updateRequest = NSBatchUpdateRequest(entity: entityDescription)
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = fetchRequest.predicate
		try context.batchUpdate(updateRequest)
	}

	public func delete() throws {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try context.batchDelete(deleteRequest)
	}
}