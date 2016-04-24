//
//  FetchRequestBuilder.swift
//  MantleData
//
//  Created by Anders on 24/4/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import CoreData

public struct FetchRequestBuilder<T: Object where T: ObjectType> {
	let context: ObjectContext

	public func make() -> T {
		guard let entityDescription = NSEntityDescription.entityForName(T.entityName, inManagedObjectContext: context) else {
			preconditionFailure("Failed to create entity description of entity `\(T.entityName)`.")
		}
		return T(entity: entityDescription, insertIntoManagedObjectContext: context)
	}

	public func finding(for ID: NSManagedObjectID) -> T {
		assert(ID.entity.name == T.entityName, "Entity does not match with the ID.")
		return try! context.existingObjectWithID(ID) as! T
	}

	public func finding(for IDs: [NSManagedObjectID]) -> [T] {
		var objects = [T]()
		for ID in IDs {
			assert(ID.entity.name == T.entityName, "Entity does not match with the ID.")
			objects.append(try! context.existingObjectWithID(ID) as! T)
		}
		return objects
	}

	public var all: ResultProducer<T> {
		return filtering(using: nil)
	}

	public func filtering(using predicate: NSPredicate?) -> ResultProducer<T> {
		return ResultProducer(entityName: T.entityName, predicate: predicate, context: context)
	}

	public func filtering(usingFormat formatString: String, arguments: AnyObject...) -> ResultProducer<T> {
		return filtering(usingFormat: formatString, argumentArray: arguments)
	}

	public func filtering(usingFormat formatString: String, argumentArray: [AnyObject]) -> ResultProducer<T> {
		let predicate = NSPredicate(format: formatString, argumentArray: argumentArray)
		return ResultProducer(entityName: T.entityName, predicate: predicate, context: context)
	}
}