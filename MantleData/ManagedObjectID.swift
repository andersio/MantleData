//
//  ManagedObjectID.swift
//  MantleData
//
//  Created by Anders on 20/6/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import CoreData

public struct ManagedObjectID<E: NSManagedObject> {
	public let id: NSManagedObjectID
	public var isTemporaryID: Bool {
		return id.isTemporaryID
	}

	public init(object: E) {
		id = object.objectID
	}

	public func object(for context: NSManagedObjectContext) -> E {
		return context.object(with: id) as! E
	}
}

extension ManagedObjectID: Hashable {
	public var hashValue: Int {
		return id.uriRepresentation().hashValue
	}
}

public func ==<E: NSManagedObject>(left: ManagedObjectID<E>, right: ManagedObjectID<E>) -> Bool {
	return left.id.uriRepresentation() == right.id.uriRepresentation()
}
