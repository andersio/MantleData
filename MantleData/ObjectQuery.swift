//
//  LazyObjectCollection.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData
import ReactiveCocoa

public enum SortingKey {
	case ascending(keyPath: String)
	case descending(keyPath: String)
}

/// **ObjectQuery**
public class ObjectQuery<E: NSManagedObject> {
	public typealias Entity = E

	var context: NSManagedObjectContext
	var fetchRequest: NSFetchRequest<Entity>
	var hasGroupByKeyPath = false

	public init(context: NSManagedObjectContext) {
		guard let entityDescription = NSEntityDescription.entity(forEntityName: String(Entity),
		                                                                in: context) else {
			preconditionFailure("Failed to create entity description of entity `\(String(Entity))`.")
		}

		let fetchRequest = NSFetchRequest<Entity>()
		fetchRequest.entity = entityDescription

		self.context = context
		self.fetchRequest = fetchRequest
	}

	public func fetchInBackground() -> SignalProducer<[Entity], NSError> {
		return SignalProducer { observer, disposable in
			self.fetchRequest.resultType = []

			let asyncFetchRequest = NSAsynchronousFetchRequest(fetchRequest: self.fetchRequest) { fetchResult in
				let storage = fetchResult.finalResult ?? []
				observer.sendCompleted(with: storage)
			}

			do {
				_ = try self.context.execute(asyncFetchRequest)
			} catch let error {
				observer.sendFailed(error as NSError)
			}
		}
	}

	public func fetch() throws -> [Entity] {
		return try context.fetch(fetchRequest)
	}
}

extension ObjectQuery {
	public func filter(using predicate: Predicate?) -> ObjectQuery {
		return self
	}

	public func filter(by expression: String, _ arguments: AnyObject...) -> ObjectQuery {
		return filter(by: expression, with: arguments)
	}

	public func filter(by expression: String, with argumentArray: [AnyObject]) -> ObjectQuery {
		fetchRequest.predicate = Predicate(format: expression, argumentArray: argumentArray)
		return self
	}

  /// MARK: Ordering operators
  
  public func sort(by keys: SortingKey...) -> ObjectQuery {
		if fetchRequest.sortDescriptors == nil {
			fetchRequest.sortDescriptors = []
		}

		for key in keys {
			let sortDescriptor: SortDescriptor

			switch key {
			case let .ascending(keyPath):
				sortDescriptor = SortDescriptor(key: keyPath, ascending: true)
			case let .descending(keyPath):
				sortDescriptor = SortDescriptor(key: keyPath, ascending: false)
			}

			fetchRequest.sortDescriptors!.append(sortDescriptor)
		}

		return self
  }
  
  public func group(by key: SortingKey) -> ObjectQuery {
		precondition(!hasGroupByKeyPath, "You can only group by one key path.")
		hasGroupByKeyPath = true

		if fetchRequest.sortDescriptors == nil {
			fetchRequest.sortDescriptors = []
		}

		let sortDescriptor: SortDescriptor
		switch key {
		case let .ascending(keyPath):
			sortDescriptor = SortDescriptor(key: keyPath, ascending: true)
		case let .descending(keyPath):
			sortDescriptor = SortDescriptor(key: keyPath, ascending: false)
		}
		fetchRequest.sortDescriptors!.insert(sortDescriptor, at: 0)

		return self
	}
}

/// MARK: Factories

extension ObjectQuery {
	public func makeObjectSet(prefetching policy: ObjectSetPrefetchingPolicy = .none) -> ObjectSet<Entity> {
		let sectionNameKeyPath: String? = hasGroupByKeyPath ? fetchRequest.sortDescriptors!.first!.key! : nil
		return ObjectSet(for: fetchRequest,
		                 in: context,
		                 prefetchingPolicy: policy,
		                 sectionNameKeyPath: sectionNameKeyPath)
	}

	#if os(iOS)
	public func makeController() -> NSFetchedResultsController<Entity> {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<Entity>
		return NSFetchedResultsController(fetchRequest: fetchRequest,
		                                  managedObjectContext: context,
		                                  sectionNameKeyPath: hasGroupByKeyPath ? fetchRequest.sortDescriptors!.first!.key! : nil,
		                                  cacheName: nil)
	}
	#endif
}

/// MARK: Others

extension ObjectQuery {
	private func fetchingDictionary(using fetchRequest: NSFetchRequest<NSDictionary>) throws -> [[String: AnyObject]] {
		fetchRequest.resultType = .dictionaryResultType
		return try context.fetch(fetchRequest).map { $0 as! [String: AnyObject] }
	}

	public var resultingIDs: [NSManagedObjectID] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSManagedObjectID>
		fetchRequest.resultType = .managedObjectIDResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return try! context.fetch(fetchRequest)
	}

	public var resultingCount: Int {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSFetchRequestResult>
		fetchRequest.resultType = .countResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return try! context.count(for: fetchRequest)
	}

	/// Aggregate Functions

	private func aggregate(usingFunction name: String, onKeyPath keyPath: String) throws -> [String: AnyObject]? {
		return try aggregate((name, keyPath))?.first
	}

	private func aggregate(_ functions: (name: String, keyPath: String)...) throws -> [[String: AnyObject]]? {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSDictionary>

		let expressions = functions.map { descriptor -> NSExpressionDescription in
			let expression = NSExpressionDescription()
			expression.name = descriptor.name
			expression.expression = NSExpression(forFunction: "\(descriptor.name):",
																					 arguments: [NSExpression(forKeyPath: descriptor.keyPath)])
			expression.expressionResultType = .integer64AttributeType
			return expression
		}

		fetchRequest.resultType = .dictionaryResultType
		fetchRequest.propertiesToFetch = expressions

		let results = try fetchingDictionary(using: fetchRequest)
		return results
	}

	private func aggregate(usingFunction name: String, onKeyPath keyPath: String, groupByKeyPath groupingKeyPath: String) throws -> [Int] {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSDictionary>
		let expression = NSExpressionDescription()
		expression.name = name
		expression.expression = NSExpression(forFunction: "\(name):", arguments: [NSExpression(forKeyPath: keyPath)])
		expression.expressionResultType = .integer64AttributeType

		fetchRequest.propertiesToFetch = [expression, groupingKeyPath]
		fetchRequest.propertiesToGroupBy = [groupingKeyPath]

		let results = try fetchingDictionary(using: fetchRequest)
		return results.map { Int(cocoaValue: $0[name]) }
	}

	public func count(ofKeyPath keyPath: String) throws -> Int {
		return try (aggregate(usingFunction: "count", onKeyPath: keyPath)?["count"] as? NSNumber)?.intValue ?? 0
	}

	public func sum(ofKeyPath keyPath: String) throws -> Int {
		return try (aggregate(usingFunction: "sum", onKeyPath: keyPath)?["sum"] as? NSNumber)?.intValue ?? 0
	}

	public func min(ofKeyPath keyPath: String) throws -> Int? {
		return try (aggregate(usingFunction: "min", onKeyPath: keyPath)?[keyPath] as? NSNumber)?.intValue ?? 0
	}

	public func max(ofKeyPath keyPath: String) throws -> Int? {
		return try (aggregate(usingFunction: "max", onKeyPath: keyPath)?[keyPath] as? NSNumber)?.intValue ?? 0
	}

	public func count(onKeyPath keyPath: String, groupByKeyPath groupingKeyPath: String) throws -> [Int] {
		return try aggregate(usingFunction: "count", onKeyPath: keyPath, groupByKeyPath: groupingKeyPath)
	}

	public func sum(onKeyPath keyPath: String, groupByKeyPath groupingKeyPath: String) throws -> [Int] {
		return try aggregate(usingFunction: "sum", onKeyPath: keyPath, groupByKeyPath: groupingKeyPath)
	}

	public func min(onKeyPath keyPath: String, groupByKeyPath groupingKeyPath: String) throws -> [Int] {
		return try aggregate(usingFunction: "min", onKeyPath: keyPath, groupByKeyPath: groupingKeyPath)
	}

	public func max(onKeyPath keyPath: String, groupByKeyPath groupingKeyPath: String) throws -> [Int] {
		return try aggregate(usingFunction: "max", onKeyPath: keyPath, groupByKeyPath: groupingKeyPath)
	}

	public func minMax(ofKeyPath keyPath: String) throws -> (min: Int, max: Int)? {
		let results = try aggregate(("min", keyPath), ("max", keyPath))
		return results.flatMap {
			if let dictionary = $0.first, let first = dictionary["min"] as? NSNumber, second = dictionary["max"] as? NSNumber {
				return (min: first.intValue, max: second.intValue)
			}
			return nil
		}
	}

	/// MARK: Batch Update Operators

	public func update<Value: CocoaBridgeable>(newValue value: Value, forKeyPath path: String) throws {
		try update(from: NSExpression(forConstantValue: value.cocoaValue), forKeyPath: path)
	}

	public func update(from expression: NSExpression, forKeyPath path: String) throws {
		try update([path: expression])
	}

	public func update(_ dictionary: [String: NSExpression]) throws {
		guard let entityDescription = NSEntityDescription.entity(forEntityName: String(Entity), in: context) else {
			preconditionFailure("Failed to create entity description of entity `\(String(Entity))`.")
		}

		let updateRequest = NSBatchUpdateRequest(entity: entityDescription)
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = fetchRequest.predicate
		try context.batchUpdate(updateRequest)
	}

	public func unsafeBatchDelete() throws {
		let fetchRequest = self.fetchRequest.copy() as! NSFetchRequest<NSFetchRequestResult>
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try context.batchDelete(deleteRequest)
	}
}
