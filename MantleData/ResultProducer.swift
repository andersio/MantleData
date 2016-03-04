//
//  ResultProducer.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import CoreData

final public class ResultProducer<Entity: Object> {
  private let context: ObjectContext
  private let entityName: String
  private var fetchRequest: NSFetchRequest
  private var sectionNameKeyPath: String?

  private func prepareRequest() -> ObjectContext {
    guard let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context) else {
      preconditionFailure("Failed to create entity description of entity `\(entityName)`.")
    }

    fetchRequest.entity = entityDescription
    return context
  }

	private func fetchObjects(using context: ObjectContext) throws -> [Entity] {
		fetchRequest.resultType = .ManagedObjectResultType
		return try context.executeFetchRequest(fetchRequest) as! [Entity]
	}

	private func fetchDictionary(using context: ObjectContext) throws -> [[String: AnyObject]] {
		fetchRequest.resultType = .DictionaryResultType
		return try context.executeFetchRequest(fetchRequest) as! [[String: AnyObject]]
	}

	internal init(entityName: String, fetchRequest: NSFetchRequest, context: ObjectContext) {
    self.entityName = entityName
    self.fetchRequest = fetchRequest
		self.context = context
  }

	public func modifyFetchRequest(@noescape action: NSFetchRequest -> Void) {
		action(fetchRequest)
	}
  
  /// MARK: Ordering operators
  
  public func sort(byKeyPath path: String, ascending: Bool = true) -> ResultProducer {
    if fetchRequest.sortDescriptors == nil {
      fetchRequest.sortDescriptors = []
    }
    
    fetchRequest.sortDescriptors!.append(NSSortDescriptor(key: path, ascending: ascending))
    
    return self
  }
  
  public func group(byKeyPath path: String, ascending: Bool = true) -> ResultProducer {
    precondition(sectionNameKeyPath == nil, "`groupBy` can only be used once.")

    if fetchRequest.sortDescriptors == nil {
      fetchRequest.sortDescriptors = []
    }
    
    sectionNameKeyPath = path
    fetchRequest.sortDescriptors!.insert(NSSortDescriptor(key: path, ascending: ascending), atIndex: 0)
    
    return self
  }

  /// MARK: Finalizers

  public var objectSet: ObjectSet<Entity> {
    let context = prepareRequest()
    return ObjectSet(fetchRequest: fetchRequest,
			context: context,
			sectionNameKeyPath: sectionNameKeyPath)
  }

	#if os(iOS)
	public var cocoaController: NSFetchedResultsController {
		let context = prepareRequest()
		return NSFetchedResultsController(fetchRequest: fetchRequest,
			managedObjectContext: context,
			sectionNameKeyPath: sectionNameKeyPath,
			cacheName: nil)
	}
	#endif
  
  public var array: [Entity] {
		return try! fetchObjects(using: prepareRequest())
	}

	private var IDs: [NSManagedObjectID] {
		let context = prepareRequest()
		fetchRequest.resultType = .ManagedObjectIDResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return try! context.executeFetchRequest(fetchRequest) as! [NSManagedObjectID]
	}

	private var count: Int {
		let context = prepareRequest()
		fetchRequest.resultType = .CountResultType
		fetchRequest.includesPropertyValues = false
		fetchRequest.includesSubentities = false
		return context.countForFetchRequest(fetchRequest, error: nil)
	}

	/// Collection Operators

	public func count(byKeyPath path: String) -> Int {
		let context = prepareRequest()
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: path)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.propertiesToFetch = [count]

		let results = try! fetchDictionary(using: context)
		return Int(cocoaValue: results.first!["count"])
	}

	public func count(byKeyPath path: String, groupByKeyPath groupByPath: String) -> [Int] {
		let context = prepareRequest()
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: path)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [count, groupByPath]
		fetchRequest.propertiesToGroupBy = [groupByPath]

		let results = try! fetchDictionary(using: context)

		return results.map {
			Int(cocoaValue: $0["count"])
		}
	}

	public func sum(byKeyPath path: String) throws -> Int {
		let context = prepareRequest()
		let sum = NSExpressionDescription()
		sum.name = "sum"
		sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: path)])
		sum.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [sum]

		let results = try fetchDictionary(using: context)

		return Int(cocoaValue: results.first!["sum"])
	}

	public func sum(byKeyPath path: String, groupByKeyPath groupByPath: String) throws -> [Int] {
		let context = prepareRequest()
		let sum = NSExpressionDescription()
		sum.name = "sum"
		sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: path)])
		sum.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [sum, groupByPath]
		fetchRequest.propertiesToGroupBy = [groupByPath]

		let results = try fetchDictionary(using: context)

		return results.map {
			Int(cocoaValue: $0["sum"])
		}
	}

	/// MARK: Batch Update Operators

	public func batchUpdate<Value: CocoaBridgeable>(newValue value: Value, forKeyPath path: String) throws {
		try batchUpdate(from: NSExpression(forConstantValue: value.cocoaValue), forKeyPath: path)
	}

	public func batchUpdate(from expression: NSExpression, forKeyPath path: String) throws {
		try batchUpdate([path: expression])
	}

	public func batchUpdate(dictionary: [String: NSExpression]) throws {
		let context = prepareRequest()
		let updateRequest = NSBatchUpdateRequest(entity: fetchRequest.entity!)
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = fetchRequest.predicate
		try context.batchUpdate(updateRequest)
	}

	public func batchDelete() throws {
		let context = prepareRequest()
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try context.batchDelete(deleteRequest)
	}
}