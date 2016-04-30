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

/// A protocol describing the ability of an object to resolve a conflict of itself.
public protocol ObjectConflictResolving: class {
	/// Resolve a conflict of `self`.
	/// - Parameter latestSnapshot: A snapshot of `self` at last save or fetch in its object context.
	/// - Parameter cachedSnapshot: A persisted snapshot of `self`.
	/// - Returns: `true` if the conflict is resolved. `false` otherwise.
	func resolveConflict(with latestSnapshot: [String: AnyObject], against cachedSnapshot: [String: AnyObject]) throws
}

/// A protocol describing the ability to resolve conflicts in a container.
public protocol ContainerConflictResolving: class {
	/// Resolve conflicts for a save request.
	/// - Parameter list: A list of conflicts.
	/// - Parameter resolver: A resolver which asks objects to resolve conflicts for themselves.
	/// - Throws: Unsuccessful attempt of conflict resolution.
	static func resolveConflicts(list: [NSMergeConflict], @noescape using resolver: [NSMergeConflict] throws -> Void) rethrows
}

extension NSManagedObject: ObjectConflictResolving {
	public class var preferredConflictResolvingPolicy: ConflictResolvingPolicy {
		return .throwError
	}

	public func resolveConflict(with latestSnapshot: [String: AnyObject], against cachedSnapshot: [String: AnyObject]) throws {
		try resolveConflict(with: latestSnapshot, against: cachedSnapshot, using: self.dynamicType.preferredConflictResolvingPolicy)
	}

	public func resolveConflict(with latestSnapshot: [String: AnyObject], against cachedSnapshot: [String: AnyObject], using policy: ConflictResolvingPolicy) throws {
		switch policy {
		case .overwrite:
			// Overwrite the store with the current values in `object`.
			break

		case .rollback:
			// Discard the changes.
			managedObjectContext?.refreshObject(self, mergeChanges: false)

		case .throwError:
			throw NSError(domain: "MantleData.Object.ConflictResolving",
										code: 0,
										userInfo: [NSLocalizedDescriptionKey:
																"Failed to resolve a conflict of an `\(entity.name)` object."])

		case .preferStore:
			// overwrite the keys with external changes.
			for (key, value) in latestSnapshot {
				if let cachedValue = cachedSnapshot[key] where !cachedValue.isEqual(value) {
					if let latestValue = primitiveValueForKey(key) where !cachedValue.isEqual(latestValue) {
						setValue(cachedValue, forKey: key)
					}
				}
			}

		case .preferObject:
			// overwrite the keys with external changes only if the key is not changed locally.
			let changes = changedValues()

			for (key, value) in latestSnapshot {
				if let cachedValue = cachedSnapshot[key] where !cachedValue.isEqual(value) {
					if !changes.keys.contains(key) {
						setValue(cachedValue, forKey: key)
					}
				}
			}
		}
	}
}

public class ObjectMergePolicy: NSMergePolicy {
	var resolver: ContainerConflictResolving.Type?

	public init(resolver: ContainerConflictResolving.Type?) {
		self.resolver = resolver ?? ObjectMergePolicy.self
		super.init(mergeType: .MergeByPropertyObjectTrumpMergePolicyType)
	}

	override public func resolveConflicts(list: [AnyObject]) throws {
		try super.resolveConflicts(list)

		let list = list as! [NSMergeConflict]

		try resolver?.resolveConflicts(list) { newList in
			for conflict in newList {
				if conflict.persistedSnapshot != nil {
					preconditionFailure("[UNIMPLEMENTED] Handler for PSC vs Store inconsistency.")
				} else {
					 try conflict.sourceObject.resolveConflict(with: conflict.objectSnapshot ?? [:],
					                                             against: conflict.cachedSnapshot ?? [:])
				}
			}
		}
	}
}

extension ObjectMergePolicy: ContainerConflictResolving {
	public static func resolveConflicts(list: [NSMergeConflict], @noescape using resolver: [NSMergeConflict] throws -> Void) rethrows {
		try resolver(list)
	}
}