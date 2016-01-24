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

	private func queryForObjectsIn(context: ObjectContext) throws -> [Entity] {
		fetchRequest.resultType = .ManagedObjectResultType
		return try context.executeFetchRequest(fetchRequest) as! [Entity]
	}

	private func queryForDictionaryIn(context: ObjectContext) throws -> [[String: AnyObject]] {
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
  
  public func sortBy(keyPath: String, ascending: Bool = true) -> ResultProducer {
    if fetchRequest.sortDescriptors == nil {
      fetchRequest.sortDescriptors = []
    }
    
    fetchRequest.sortDescriptors!.append(NSSortDescriptor(key: keyPath, ascending: ascending))
    
    return self
  }
  
  public func groupBy(keyPath: String, ascending: Bool = true) -> ResultProducer {
    precondition(sectionNameKeyPath == nil, "`groupBy` can only be used once.")

    if fetchRequest.sortDescriptors == nil {
      fetchRequest.sortDescriptors = []
    }
    
    sectionNameKeyPath = keyPath
    fetchRequest.sortDescriptors!.insert(NSSortDescriptor(key: keyPath, ascending: ascending), atIndex: 0)
    
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
		return try! queryForObjectsIn(prepareRequest())
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

	public func countOf(keyPath: String) -> Int {
		let context = prepareRequest()
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: keyPath)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.propertiesToFetch = [count]

		let results = try! queryForDictionaryIn(context)
		return Int(cocoaValue: results.first!["count"])
	}

	public func countOf(keyPath: String, groupBy groupByKeyPath: String) -> [Int] {
		let context = prepareRequest()
		let count = NSExpressionDescription()
		count.name = "count"
		count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: keyPath)])
		count.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [count, groupByKeyPath]
		fetchRequest.propertiesToGroupBy = [groupByKeyPath]

		let results = try! queryForDictionaryIn(context)

		return results.map {
			Int(cocoaValue: $0["count"])
		}
	}

	public func sumOf(keyPath: String) throws -> Int {
		let context = prepareRequest()
		let sum = NSExpressionDescription()
		sum.name = "sum"
		sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: keyPath)])
		sum.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [sum]

		let results = try queryForDictionaryIn(context)

		return Int(cocoaValue: results.first!["sum"])
	}

	public func sumOf(keyPath: String, groupBy groupByKeyPath: String) throws -> [Int] {
		let context = prepareRequest()
		let sum = NSExpressionDescription()
		sum.name = "sum"
		sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: keyPath)])
		sum.expressionResultType = .Integer64AttributeType

		fetchRequest.resultType = .DictionaryResultType
		fetchRequest.propertiesToFetch = [sum, groupByKeyPath]
		fetchRequest.propertiesToGroupBy = [groupByKeyPath]

		let results = try queryForDictionaryIn(context)

		return results.map {
			Int(cocoaValue: $0["sum"])
		}
	}

	/// MARK: Batch Update Operators

	public func updateAndSave<Value: CocoaBridgeable>(keyPath: String, value: Value) throws {
		try updateAndSave(keyPath, value: NSExpression(forConstantValue: value.cocoaValue))
	}

	public func updateAndSave(keyPath: String, value: NSExpression) throws {
		try updateAndSave([keyPath: value])
	}

	public func updateAndSave(dictionary: [String: NSExpression]) throws {
		let context = prepareRequest()
		let updateRequest = NSBatchUpdateRequest(entity: fetchRequest.entity!)
		updateRequest.propertiesToUpdate = dictionary
		updateRequest.predicate = fetchRequest.predicate
		try context.batchUpdate(updateRequest)
	}

	public func deleteAndSave() throws {
		let context = prepareRequest()
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
		try context.batchDelete(deleteRequest)
	}
}