//
//  ResultProducer.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData

public struct FetchRequestBuilder {
	public enum Order {
		case ascending
		case descending

		private var isAscending: Bool {
			if case .ascending = self {
				return true
			}

			return false
		}
	}

  private let context: ObjectContext
  private let entityName: String

	private var predicate: NSPredicate?
	private var groupingDescriptor: NSSortDescriptor?
	private var sortDescriptors: [NSSortDescriptor]?

	private func makeFetchRequest() -> NSFetchRequest {
		let request = NSFetchRequest()

		guard let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(entityName)`.")
		}

		request.entity = entityDescription
		request.predicate = predicate

		if let groupingDescriptor = groupingDescriptor {
			request.sortDescriptors = sortDescriptors != nil ? [groupingDescriptor] + sortDescriptors! : [groupingDescriptor]
		} else {
			request.sortDescriptors = sortDescriptors
		}

		return request
	}

	internal init(entity name: String, in context: ObjectContext) {
    self.entityName = name
		self.context = context
  }


	public mutating func filter(using predicate: NSPredicate?) {
		self.predicate = predicate
	}

	public mutating func filter(usingFormat formatString: String, arguments: AnyObject...) {
		filter(usingFormat: formatString, argumentArray: arguments)
	}

	public mutating func filter(usingFormat formatString: String, argumentArray: [AnyObject]) {
		predicate = NSPredicate(format: formatString, argumentArray: argumentArray)
	}

  /// MARK: Ordering operators
  
  public mutating func sort(byKeyPath path: String, order: Order = .ascending) {
		if sortDescriptors == nil {
			sortDescriptors = []
		}

    sortDescriptors!.append(NSSortDescriptor(key: path, ascending: order.isAscending))
  }
  
  public mutating func group(byKeyPath path: String, order: Order = .ascending) {
    groupingDescriptor = NSSortDescriptor(key: path, ascending: order.isAscending)
	}
}

public struct ResultProducer<Entity: Object> {
	private let builder: FetchRequestBuilder

	internal init(builder: FetchRequestBuilder) {
		self.builder = builder
	}

  /// MARK: Result Finalizers

  public var resultObjectSet: ObjectSet<Entity> {
    let fetchRequest = builder.makeFetchRequest()
    return ObjectSet(fetchRequest: fetchRequest,
			context: builder.context,
			sectionNameKeyPath: builder.groupingDescriptor?.key)
  }

	#if os(iOS)
	public var resultCocoaController: NSFetchedResultsController {
		let fetchRequest = builder.makeFetchRequest()
		return NSFetchedResultsController(fetchRequest: fetchRequest,
			managedObjectContext: builder.context,
			sectionNameKeyPath: builder.groupingDescriptor?.key,
			cacheName: nil)
	}
	#endif

	private func fetchingObjects(using fetchRequest: NSFetchRequest) throws -> [Entity] {
		fetchRequest.resultType = .ManagedObjectResultType
		return try builder.context.executeFetchRequest(fetchRequest) as! [Entity]
	}

	private func fetchingDictionary(using fetchRequest: NSFetchRequest) throws -> [[String: AnyObject]] {
		fetchRequest.resultType = .DictionaryResultType
		return try builder.context.executeFetchRequest(fetchRequest) as! [[String: AnyObject]]
	}

  public var resultArray: [Entity] {
		return try! fetchingObjects(using: builder.makeFetchRequest())
	}

	public var resultIDs: [NSManagedObjectID] {
		let fetchRequest = builder.makeFetchRequest()
		fetchRequest.resultType = .ManagedObjectIDResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return try! builder.context.executeFetchRequest(fetchRequest) as! [NSManagedObjectID]
	}

	public var resultCount: Int {
		let fetchRequest = builder.makeFetchRequest()
		fetchRequest.resultType = .CountResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return builder.context.countForFetchRequest(fetchRequest, error: nil)
	}

	/// Aggregate Functions

	public func count(ofKeyPath path: String) -> Int {
		let fetchRequest = builder.makeFetchRequest()
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: path)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.propertiesToFetch = [count]

		let results = try! fetchingDictionary(using: fetchRequest)
		return Int(cocoaValue: results.first!["count"])
	}

	public func count(ofKeyPath path: String, groupByKeyPath groupByPath: String) -> [Int] {
		let fetchRequest = builder.makeFetchRequest()
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
		let fetchRequest = builder.makeFetchRequest()
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
		let fetchRequest = builder.makeFetchRequest()
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
		guard let entityDescription = NSEntityDescription.entityForName(builder.entityName, inManagedObjectContext: builder.context) else {
			preconditionFailure("Failed to create entity description of entity `\(builder.entityName)`.")
		}

		let updateRequest = NSBatchUpdateRequest(entity: entityDescription)
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = builder.predicate
		try builder.context.batchUpdate(updateRequest)
	}

	public func delete() throws {
		let fetchRequest = builder.makeFetchRequest()
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try builder.context.batchDelete(deleteRequest)
	}
}