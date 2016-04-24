//
//  ResultProducer.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData

public class ResultProducer<Entity: Object> {
  private let context: ObjectContext
  private let entityName: String

	private let predicate: NSPredicate?
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

	private func fetchingObjects(using fetchRequest: NSFetchRequest) throws -> [Entity] {
		fetchRequest.resultType = .ManagedObjectResultType
		return try context.executeFetchRequest(fetchRequest) as! [Entity]
	}

	private func fetchingDictionary(using fetchRequest: NSFetchRequest) throws -> [[String: AnyObject]] {
		fetchRequest.resultType = .DictionaryResultType
		return try context.executeFetchRequest(fetchRequest) as! [[String: AnyObject]]
	}

	internal init(entityName: String, predicate: NSPredicate?, context: ObjectContext) {
    self.entityName = entityName
    self.predicate = predicate
		self.context = context
  }

  /// MARK: Ordering operators
  
  public func sorting(byKeyPath path: String, ascending: Bool = true) -> ResultProducer {
		if sortDescriptors == nil {
			sortDescriptors = []
		}

    sortDescriptors!.append(NSSortDescriptor(key: path, ascending: ascending))

    return self
  }
  
  public func grouping(byKeyPath path: String, ascending: Bool = true) -> ResultProducer {
    groupingDescriptor = NSSortDescriptor(key: path, ascending: ascending)
    
    return self
  }

  /// MARK: Result Finalizers

  public var resultObjectSet: ObjectSet<Entity> {
    let fetchRequest = makeFetchRequest()
    return ObjectSet(fetchRequest: fetchRequest,
			context: context,
			sectionNameKeyPath: groupingDescriptor?.key)
  }

	#if os(iOS)
	public var resultCocoaController: NSFetchedResultsController {
		let fetchRequest = makeFetchRequest()
		return NSFetchedResultsController(fetchRequest: fetchRequest,
			managedObjectContext: context,
			sectionNameKeyPath: groupingDescriptor?.key,
			cacheName: nil)
	}
	#endif
  
  public var resultArray: [Entity] {
		return try! fetchingObjects(using: makeFetchRequest())
	}

	public var resultIDs: [NSManagedObjectID] {
		let fetchRequest = makeFetchRequest()
		fetchRequest.resultType = .ManagedObjectIDResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return try! context.executeFetchRequest(fetchRequest) as! [NSManagedObjectID]
	}

	public var resultCount: Int {
		let fetchRequest = makeFetchRequest()
		fetchRequest.resultType = .CountResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return context.countForFetchRequest(fetchRequest, error: nil)
	}

	/// Aggregate Functions

	public func count(ofKeyPath path: String) -> Int {
		let fetchRequest = makeFetchRequest()
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: path)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.propertiesToFetch = [count]

		let results = try! fetchingDictionary(using: fetchRequest)
		return Int(cocoaValue: results.first!["count"])
	}

	public func count(ofKeyPath path: String, groupByKeyPath groupByPath: String) -> [Int] {
		let fetchRequest = makeFetchRequest()
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
		let fetchRequest = makeFetchRequest()
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
		let fetchRequest = makeFetchRequest()
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
		guard let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(entityName)`.")
		}

		let updateRequest = NSBatchUpdateRequest(entity: entityDescription)
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = predicate
		try context.batchUpdate(updateRequest)
	}

	public func delete() throws {
		let fetchRequest = makeFetchRequest()
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try context.batchDelete(deleteRequest)
	}
}