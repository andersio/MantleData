//
//  ObjectContext.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import CoreData

/// MantleData-enriched Object Context.
/// - Important: NSManagedObjectC is extended only for providing conveinence methods and mechanics. MantleData does not alter any critical logic of the implementation.

final public class ObjectContext: NSManagedObjectContext {
	internal static let ThreadContextKey = "MDThreadContext"
	internal static let ThreadContextMutabilityKey = "MDThreadContextIsMutable"
	internal static let DidBatchUpdateNotification = "MDDidBatchUpdate"
	internal static let DidBatchDeleteNotification = "MDDidBatchDelete"
	internal static let BatchRequestResultIDs = "MDResultIDs"

	public init(persistentStoreCoordinator: NSPersistentStoreCoordinator, concurrencyType: NSManagedObjectContextConcurrencyType, mergePolicy: AnyObject) {
		super.init(concurrencyType: concurrencyType)
		self.mergePolicy = mergePolicy
		self.persistentStoreCoordinator = persistentStoreCoordinator

		let defaultCenter = NSNotificationCenter.defaultCenter()

		defaultCenter.addObserver(self,
			selector: "handleExternalBatchUpdate:",
			name: ObjectContext.DidBatchUpdateNotification,
			object: nil)

		defaultCenter.addObserver(self,
			selector: "handleExternalBatchDelete:",
			name: ObjectContext.DidBatchDeleteNotification,
			object: nil)

		defaultCenter.addObserver(self,
			selector: "handleExternalChanges:",
			name: NSManagedObjectContextDidSaveNotification,
			object: nil)
	}

	public required init?(coder aDecoder: NSCoder) {
	    super.init(coder: aDecoder)
	}

	deinit {
		let defaultCenter = NSNotificationCenter.defaultCenter()

		defaultCenter.removeObserver(self,
			name: ObjectContext.DidBatchDeleteNotification,
			object: nil)

		defaultCenter.removeObserver(self,
			name: ObjectContext.DidBatchUpdateNotification,
			object: nil)

		defaultCenter.removeObserver(self,
			name: NSManagedObjectContextDidSaveNotification,
			object: nil)
	}

  public func schedule(block: () -> Void) {
    if concurrencyType == .MainQueueConcurrencyType && NSThread.isMainThread() {
      block()
    } else {
      super.performBlock(block)
		}
	}

	public func prepare<Result>(@noescape block: () -> Result) -> Result {
		if concurrencyType == .MainQueueConcurrencyType && NSThread.isMainThread() {
			return block()
		} else {
			var returnResult: Result!
			super.performBlockAndWaitNoEscape {
				returnResult = block()
			}
			return returnResult
		}
	}

  public func perform(@noescape block: () -> Void) {
    if concurrencyType == .MainQueueConcurrencyType && NSThread.isMainThread() {
			block()
    } else {
      super.performBlockAndWaitNoEscape(block)
    }
	}

	/// Synchronously batch updating properties of objects, constrained by a predicate.
	/// - Important: Deadlock if you call this from remote contexts, since it would synchronously update remote contexts after the persistent store result returns.
	public func batchUpdate(request: NSBatchUpdateRequest) throws {
		request.resultType = .UpdatedObjectIDsResultType

		guard let requestResult = try self.executeRequest(request) as? NSBatchUpdateResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let objectIDs = requestResult.result as? [NSManagedObjectID] else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result ID array for a batch update request.")
		}

		updateObjectsWith(objectIDs)

		NSNotificationCenter.defaultCenter().postNotificationName(ObjectContext.DidBatchUpdateNotification,
			object: self,
			userInfo: [ObjectContext.BatchRequestResultIDs: objectIDs])
	}

	/// Synchronously batch deleting objects, constrained by a predicate.
	/// - Important: Deadlock if you call this from remote contexts, since it would synchronously update remote contexts after the persistent store result returns.
	public func batchDelete(request: NSBatchDeleteRequest) throws {
		request.resultType = .ResultTypeObjectIDs

		guard let requestResult = try self.executeRequest(request) as? NSBatchDeleteResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let objectIDs = requestResult.result as? [NSManagedObjectID] else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result ID array for a batch delete request.")
		}

		deleteObjectsWith(objectIDs)

		NSNotificationCenter.defaultCenter().postNotificationName(ObjectContext.DidBatchDeleteNotification,
			object: self,
			userInfo: [ObjectContext.BatchRequestResultIDs: objectIDs])
	}

	private func isSiblingContextOf(object: AnyObject?) -> Bool {
		if let context = object as? NSManagedObjectContext {
			if context !== self && context.persistentStoreCoordinator === persistentStoreCoordinator {
				return true
			}
		}

		return false
	}

	@objc public func handleExternalChanges(notification: NSNotification) {
		if isSiblingContextOf(notification.object) {
			performBlockAndWait {
				self.mergeChangesFromContextDidSaveNotification(notification)
			}
		}
	}

	@objc public func handleExternalBatchDelete(notification: NSNotification) {
		if isSiblingContextOf(notification.object) {
			performBlockAndWait {
				guard let resultIDs = notification.userInfo?[ObjectContext.BatchRequestResultIDs] as? [NSManagedObjectID] else {
					return
				}

				self.deleteObjectsWith(resultIDs)
			}
		}
	}

	private func deleteObjectsWith(resultIDs: [NSManagedObjectID]) {
		for ID in resultIDs {
			if let object = self.objectRegisteredForID(ID) {
				self.deleteObject(object)
			}
		}
	}

	@objc public func handleExternalBatchUpdate(notification: NSNotification) {
		if isSiblingContextOf(notification.object) {
			performBlockAndWait {
				guard let resultIDs = notification.userInfo?[ObjectContext.BatchRequestResultIDs] as? [NSManagedObjectID] else {
					return
				}

				self.updateObjectsWith(resultIDs)
			}
		}
	}

	private func updateObjectsWith(resultIDs: [NSManagedObjectID]) {
		// Force the context to discard the cached data.
		let previousInterval = stalenessInterval
		stalenessInterval = 0

		for ID in resultIDs {
			if let object = objectRegisteredForID(ID) {
				refreshObject(object, mergeChanges: true)
			}
		}

		stalenessInterval = previousInterval
	}
}