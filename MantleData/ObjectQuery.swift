//
//  LazyObjectCollection.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveSwift

public enum SortingKeyPath {
	case ascending(String)
	case descending(String)

	public var keyPath: String {
		switch self {
		case let .ascending(value):
			return value

		case let .descending(value):
			return value
		}
	}

	public var sortDescriptor: NSSortDescriptor {
		switch self {
		case let .ascending(value):
			return NSSortDescriptor(key: value, ascending: true)

		case let .descending(value):
			return NSSortDescriptor(key: value, ascending: false)
		}
	}
}

public final class ObjectQuery<E: NSManagedObject> {
	public typealias Entity = E

	let context: NSManagedObjectContext
	let fetchRequest: NSFetchRequest<Entity>
	var groupByKeyPath: SortingKeyPath?

	internal init(in context: NSManagedObjectContext) {
		let fetchRequest = NSFetchRequest<Entity>()
		fetchRequest.entity = Entity.entity(in: context)

		self.context = context
		self.fetchRequest = fetchRequest
	}

	// - MARK: Fetching

	public func fetch() throws -> [Entity] {
		return try context.fetch(fetchRequest)
	}

	public func asyncFetch() -> SignalProducer<[Entity], NSError> {
		return SignalProducer { observer, disposable in
			self.context.async {
				self.fetchRequest.resultType = []

				let asyncFetchRequest = NSAsynchronousFetchRequest(fetchRequest: self.fetchRequest) { fetchResult in
					let storage = fetchResult.finalResult ?? []
					observer.send(value: storage)
					observer.sendCompleted()
				}

				do {
					_ = try self.context.execute(asyncFetchRequest)
				} catch let error {
					observer.send(error: error as NSError)
				}
			}
		}
	}

	private func fetchDictionary(using fetchRequest: NSFetchRequest<NSDictionary>) throws -> [[String: AnyObject]] {
		fetchRequest.resultType = .dictionaryResultType
		return try context.fetch(fetchRequest).map { $0 as! [String: AnyObject] }
	}

	public func fetchDictionary(keyPaths: [String]? = nil) -> [[String: AnyObject]] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSDictionary>
		fetchRequest.propertiesToFetch = keyPaths
		return try! fetchDictionary(using: fetchRequest)
	}

	public func fetchIds() -> [NSManagedObjectID] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSManagedObjectID>
		fetchRequest.resultType = .managedObjectIDResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false

		return try! context.fetch(fetchRequest)
	}

	public func count() -> Int {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSFetchRequestResult>
		fetchRequest.resultType = .countResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false

		return try! context.count(for: fetchRequest)
	}

	// - MARK: Filtering

	public func filter(by predicate: NSPredicate) -> ObjectQuery {
		fetchRequest.predicate = predicate
		return self
	}

	public func filter(by expression: String, _ arguments: Any...) -> ObjectQuery {
		return filter(by: expression, with: arguments)
	}

	public func filter(by expression: String, with argumentArray: [Any]) -> ObjectQuery {
		fetchRequest.predicate = NSPredicate(format: expression, argumentArray: argumentArray)
		return self
	}

  /// - MARK: Ordering
  
  public func sort(by keyPaths: SortingKeyPath...) -> ObjectQuery {
		if fetchRequest.sortDescriptors == nil {
			fetchRequest.sortDescriptors = []
		}

		for key in keyPaths {
			let sortDescriptor: NSSortDescriptor

			switch key {
			case let .ascending(keyPath):
				sortDescriptor = NSSortDescriptor(key: keyPath, ascending: true)
			case let .descending(keyPath):
				sortDescriptor = NSSortDescriptor(key: keyPath, ascending: false)
			}

			fetchRequest.sortDescriptors!.append(sortDescriptor)
		}

		return self
  }

	/// - MARK: Grouping
  
  public func group(by keyPath: SortingKeyPath) -> ObjectQuery {
		precondition(groupByKeyPath == nil, "You can only group by one key path.")
		groupByKeyPath = keyPath

		fetchRequest.sortDescriptors = fetchRequest.sortDescriptors ?? []
		fetchRequest.sortDescriptors!.insert(keyPath.sortDescriptor, at: 0)

		return self
	}

	/// - MARK: Change Tracking Collections

	public func makeCollection(prefetching policy: ObjectCollectionPrefetchingPolicy = .none) -> ObjectCollection<Entity> {
		let copy = self.fetchRequest.copy() as! NSFetchRequest<Entity>

		return ObjectCollection(for: copy,
		                        in: context,
		                        prefetchingPolicy: policy,
		                        sectionNameKeyPath: groupByKeyPath?.keyPath)
	}

	@available(macOS 10.12, *)
	public func makeController() -> NSFetchedResultsController<Entity> {
		let copy = self.fetchRequest.copy() as! NSFetchRequest<Entity>

		return NSFetchedResultsController(fetchRequest: copy,
		                                  managedObjectContext: context,
		                                  sectionNameKeyPath: groupByKeyPath?.keyPath,
		                                  cacheName: nil)
	}

	/// - MARK: Aggregations

	private func aggregate(op: String, keyPath: String, resultKey: String, default: Int? = nil) throws -> Int? {
		if let array = try aggregate(shouldGroup: false, descriptors: (op, keyPath)),
		   let result = array.first?[resultKey] as? NSNumber {
			return result.intValue
		}

		return `default`
	}

	private func groupedAggregate(op: String, keyPath: String, resultKey: String) throws -> [AnyHashable: Int] {
		var results = [AnyHashable: Int]()

		if let dictionaries = try aggregate(shouldGroup: true, descriptors: (op, keyPath)) {
			for dictionary in dictionaries {
				if let group = dictionary[keyPath] as? NSObject,
				   let result = dictionary[resultKey] as? NSNumber {
					results[AnyHashable(group)] = result.intValue
				}
			}
		}

		return results
	}

	private func aggregate(shouldGroup: Bool, descriptors: (name: String, keyPath: String)...) throws -> [[String: AnyObject]]? {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSDictionary>

		let expressions = descriptors.map { descriptor -> NSExpressionDescription in
			let expression = NSExpressionDescription()
			expression.name = descriptor.name
			expression.expression = NSExpression(forFunction: "\(descriptor.name):",
																					 arguments: [NSExpression(forKeyPath: descriptor.keyPath)])
			expression.expressionResultType = .integer64AttributeType
			return expression
		}

		if shouldGroup, let keyPath = groupByKeyPath?.keyPath {
			fetchRequest.propertiesToFetch = (expressions as [Any]) + [keyPath]
			fetchRequest.propertiesToGroupBy = [keyPath]
		} else {
			fetchRequest.propertiesToFetch = expressions
		}

		let results = try fetchDictionary(using: fetchRequest)
		return results
	}

	public func count(keyPath: String) throws -> Int {
		return try aggregate(op: "count",
		                     keyPath: keyPath,
		                     resultKey: "count",
		                     default: 0)!
	}

	public func sum(keyPath: String) throws -> Int {
		return try aggregate(op: "sum",
		                     keyPath: keyPath,
		                     resultKey: "sum",
		                     default: 0)!
	}

	public func min(keyPath: String) throws -> Int? {
		return try aggregate(op: "min",
		                     keyPath: keyPath,
		                     resultKey: keyPath)!
	}

	public func max(keyPath: String) throws -> Int? {
		return try aggregate(op: "max",
		                     keyPath: keyPath,
		                     resultKey: keyPath)!
	}

	public func groupedCount(keyPath: String) throws -> [AnyHashable: Int] {
		return try groupedAggregate(op: "count",
		                                 keyPath: keyPath,
		                                 resultKey: "count")
	}

	public func groupedSum(keyPath: String) throws -> [AnyHashable: Int] {
		return try groupedAggregate(op: "sum",
		                                 keyPath: keyPath,
		                                 resultKey: "sum")
	}

	public func groupedMin(keyPath: String) throws -> [AnyHashable: Int] {
		return try groupedAggregate(op: "min",
		                                 keyPath: keyPath,
		                                 resultKey: keyPath)
	}

	public func groupedMax(keyPath: String) throws -> [AnyHashable: Int] {
		return try groupedAggregate(op: "max",
		                                 keyPath: keyPath,
		                                 resultKey: keyPath)
	}

	/// MARK: Batch Updating

	@available(iOS 9.0, *)
	public func unsafeUpdate<Value: CocoaBridgeable>(newValue value: Value, forKeyPath path: String) throws {
		try unsafeUpdate(from: NSExpression(forConstantValue: value.cocoaValue), forKeyPath: path)
	}

	@available(iOS 9.0, *)
	public func unsafeUpdate(from expression: NSExpression, forKeyPath path: String) throws {
		try unsafeUpdate([path: expression])
	}

	@available(iOS 9.0, *)
	public func unsafeUpdate(_ dictionary: [String: NSExpression]) throws {
		let updateRequest = NSBatchUpdateRequest(entity: Entity.entity(in: context))
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = fetchRequest.predicate
		try context.batchUpdate(updateRequest)
	}

	@available(iOS 9.0, macOS 10.11, *)
	public func unsafeBatchDelete() throws {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSFetchRequestResult>
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try context.batchDelete(deleteRequest)
	}
}
