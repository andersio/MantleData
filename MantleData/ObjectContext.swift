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

public enum ContextParent {
	case PersistentStore(NSPersistentStoreCoordinator)
	case Context(ObjectContext)
}

final public class ObjectContext: NSManagedObjectContext {
	internal static let ThreadContextKey = "MDThreadContext"
	internal static let ThreadContextMutabilityKey = "MDThreadContextIsMutable"
	internal static let DidBatchUpdateNotification = "MDDidBatchUpdate"
	internal static let DidBatchDeleteNotification = "MDDidBatchDelete"
	internal static let BatchRequestResultIDs = "MDResultIDs"

	public var shouldMergeExternalChanges: Bool = false {
		/// NOTE: didSet works on only the subsequent changes to the initial value.
		didSet {
			if oldValue != shouldMergeExternalChanges {
				if shouldMergeExternalChanges {
					NSNotificationCenter.defaultCenter()
						.addObserver(self,
						             selector: #selector(ObjectContext.handleExternalChanges(_:)),
						             name: NSManagedObjectContextDidSaveNotification,
						             object: nil)
				} else {
					NSNotificationCenter.defaultCenter()
						.removeObserver(self,
						                name: NSManagedObjectContextDidSaveNotification,
						                object: nil)
				}
			}
		}
	}

	public var shouldMergeBatchRequests: Bool = false {
		didSet {
			if oldValue != shouldMergeBatchRequests {
				if shouldMergeBatchRequests {
					let defaultCenter = NSNotificationCenter.defaultCenter()

					defaultCenter.addObserver(self,
					                          selector: #selector(ObjectContext.handleExternalBatchUpdate(_:)),
					                          name: ObjectContext.DidBatchUpdateNotification,
					                          object: nil)

					defaultCenter.addObserver(self,
					                          selector: #selector(ObjectContext.handleExternalBatchDelete(_:)),
					                          name: ObjectContext.DidBatchDeleteNotification,
					                          object: nil)
				} else {
					let defaultCenter = NSNotificationCenter.defaultCenter()

					defaultCenter.removeObserver(self,
					                             name: ObjectContext.DidBatchDeleteNotification,
					                             object: nil)

					defaultCenter.removeObserver(self,
					                             name: ObjectContext.DidBatchUpdateNotification,
					                             object: nil)
				}
			}
		}
	}

	public init(parent: ContextParent, concurrencyType: NSManagedObjectContextConcurrencyType) {
		super.init(concurrencyType: concurrencyType)

		switch parent {
		case let .PersistentStore(persistentStoreCoordinator):
			self.persistentStoreCoordinator = persistentStoreCoordinator

		case let .Context(context):
			self.parentContext = context
		}

		/// NOTE: Workaround for `didSet` not working in `init` directly.
		{
			shouldMergeExternalChanges = true
			shouldMergeBatchRequests = true
		}()
	}

	public required init?(coder aDecoder: NSCoder) {
	    super.init(coder: aDecoder)
	}

	deinit {
		shouldMergeExternalChanges = false
		shouldMergeBatchRequests = false
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

	/// Batch update objects, and update other contexts asynchronously.
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

	/// Batch delete objects, and update other contexts asynchronously.
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

	private func deleteObjectsWith(resultIDs: [NSManagedObjectID]) {
		for ID in resultIDs {
			if let object = self.objectRegisteredForID(ID) {
				self.deleteObject(object)
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

	private func isSiblingOf(other: NSManagedObjectContext) -> Bool {
		if other !== self {
			// Fast Paths
			if let persistentStoreCoordinator = persistentStoreCoordinator
				 where persistentStoreCoordinator == other.persistentStoreCoordinator {
				return true
			}

			if let parentContext = parentContext where parentContext == other.parentContext {
				return true
			}

			// Slow Path
			var myPSC = persistentStoreCoordinator
			var otherPSC = other.persistentStoreCoordinator
			var myContext: NSManagedObjectContext = self
			var otherContext: NSManagedObjectContext = other

			while let parent = myContext.parentContext {
				myContext = parent
				myPSC = myContext.persistentStoreCoordinator
			}

			while let parent = otherContext.parentContext {
				otherContext = parent
				otherPSC = otherContext.persistentStoreCoordinator
			}

			if myPSC == otherPSC {
				return true
			}
		}

		return false
	}

	@objc public func handleExternalChanges(notification: NSNotification) {
		if let context = notification.object as? NSManagedObjectContext where self.isSiblingOf(context) {
			performBlock {
				self.mergeChangesFromContextDidSaveNotification(notification)
			}
		}
	}

	@objc public func handleExternalBatchDelete(notification: NSNotification) {
		if let context = notification.object as? NSManagedObjectContext where self.isSiblingOf(context) {
			performBlock {
				guard let resultIDs = notification.userInfo?[ObjectContext.BatchRequestResultIDs] as? [NSManagedObjectID] else {
					return
				}

				self.deleteObjectsWith(resultIDs)
			}
		}
	}

	@objc public func handleExternalBatchUpdate(notification: NSNotification) {
		if let context = notification.object as? NSManagedObjectContext where self.isSiblingOf(context) {
			performBlock {
				guard let resultIDs = notification.userInfo?[ObjectContext.BatchRequestResultIDs] as? [NSManagedObjectID] else {
					return
				}

				self.updateObjectsWith(resultIDs)
			}
		}
	}
}