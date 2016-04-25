//
//  ConflictResolving+MergePolicy.swift
//  MantleData
//
//  Created by Anders on 25/4/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import CoreData

public enum ConflictResolvingPolicy {
	case preferObject
	case preferStore
	case overwrite
	case rollback
	case throwError
}

public protocol ConflictResolving: class {
	/// Resolve the conflict of the supplied object.
	/// - Parameter object: The object to be resolved.
	/// - Parameter latestSnapshot: A snapshot of the object at last save or fetch.
	/// - Parameter cachedSnapshot: A snapshot of the persistence store coordinator version of the object.
	/// - Returns: `true` if the conflict is resolved. `false` otherwise.
	static func resolveConflict(of object: NSManagedObject, with latestSnapshot: [String: AnyObject], against cachedSnapshot: [String: AnyObject]) -> Bool
}

extension ConflictResolving {
	public static func resolveConflict(of object: NSManagedObject, with latestSnapshot: [String: AnyObject], against cachedSnapshot: [String: AnyObject], using policy: ConflictResolvingPolicy) -> Bool {
		switch policy {
		case .overwrite:
			// Overwrite the store with the current values in `object`.
			return true

		case .rollback:
			// Discard the changes.
			object.managedObjectContext?.refreshObject(object, mergeChanges: false)
			return true

		case .throwError:
			return false

		case .preferStore:
			// overwrite the keys with external changes.
			for (key, value) in latestSnapshot {
				if let cachedValue = cachedSnapshot[key] where !cachedValue.isEqual(value) {
					if let latestValue = object.primitiveValueForKey(key) where !cachedValue.isEqual(latestValue) {
						object.setValue(cachedValue, forKey: key)
					}
				}
			}

			return true

		case .preferObject:
			// overwrite the keys with external changes only if the key is not changed locally.
			let changes = object.changedValues()

			for (key, value) in latestSnapshot {
				if let cachedValue = cachedSnapshot[key] where !cachedValue.isEqual(value) {
					if !changes.keys.contains(key) {
						object.setValue(cachedValue, forKey: key)
					}
				}
			}

			return true
		}
	}
}

extension Object: ConflictResolving {
	public class var preferredConflictResolvingPolicy: ConflictResolvingPolicy {
		return .throwError
	}

	public class func resolveConflict(of object: NSManagedObject, with latestSnapshot: [String: AnyObject], against cachedSnapshot: [String: AnyObject]) -> Bool {
		return resolveConflict(of: object, with: latestSnapshot, against: cachedSnapshot, using: preferredConflictResolvingPolicy)
	}
}

class ObjectMergePolicy: NSMergePolicy {
	static func make() -> ObjectMergePolicy {
		return ObjectMergePolicy(mergeType: .MergeByPropertyObjectTrumpMergePolicyType)
	}

	override func resolveConflicts(list: [AnyObject]) throws {
		try super.resolveConflicts(list)

		let list = list as! [NSMergeConflict]

		for conflict in list {
			if conflict.persistedSnapshot != nil {
				preconditionFailure("[UNIMPLEMENTED] Handler for PSC vs Store inconsistency.")
			} else {
				if let objectType = conflict.sourceObject.dynamicType as? ConflictResolving.Type {
					 let resolved = objectType.resolveConflict(of: conflict.sourceObject,
					                                           with: conflict.objectSnapshot ?? [:],
					                                           against: conflict.cachedSnapshot ?? [:])

					if !resolved {
						throw NSError(domain: "MantleData.ConflictResolving",
						              code: 0,
						              userInfo: [NSLocalizedDescriptionKey: "Failed to resolve a conflict of an `\(conflict.sourceObject.entity.name)` object."])
					}
				} else {
					preconditionFailure("The runtime class of the object-in-conflict does not conform to the `ConflictResolving` protocol.")
				}
			}
		}
	}
}