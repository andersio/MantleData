//
//  ObjectContext.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import CoreData

private let didBatchUpdateNotification = "MDDidBatchUpdate"
private let didBatchDeleteNotification = "MDDidBatchDelete"
private let batchRequestResultIDArrayKey = "MDResultIDs"

extension NSManagedObjectContext {
	public enum ContextParent {
		case persistentStore(NSPersistentStoreCoordinator)
		case context(NSManagedObjectContext)
	}

	public convenience init(parent: ContextParent, concurrencyType: NSManagedObjectContextConcurrencyType) {
		self.init(concurrencyType: concurrencyType)

		switch parent {
		case let .persistentStore(persistentStoreCoordinator):
			self.persistentStoreCoordinator = persistentStoreCoordinator

		case let .context(context):
			self.parentContext = context
		}
	}

	public func observeSavedChanges(from other: NSManagedObjectContext) {
		NSNotificationCenter.defaultCenter()
			.addObserver(self,
			             selector: #selector(NSManagedObjectContext.handleExternalChanges(_:)),
			             name: NSManagedObjectContextDidSaveNotification,
			             object: nil)
	}

	public func stopObservingSavedChanges(from other: NSManagedObjectContext) {
		NSNotificationCenter.defaultCenter()
			.removeObserver(self,
			                name: NSManagedObjectContextDidSaveNotification,
			                object: nil)
	}

	public func observeBatchChanges(from other: NSManagedObjectContext) {
		let defaultCenter = NSNotificationCenter.defaultCenter()

		defaultCenter.addObserver(self,
		                          selector: #selector(NSManagedObjectContext.handleExternalBatchUpdate(_:)),
		                          name: didBatchUpdateNotification,
		                          object: nil)

		defaultCenter.addObserver(self,
		                          selector: #selector(NSManagedObjectContext.handleExternalBatchDelete(_:)),
		                          name: didBatchDeleteNotification,
		                          object: nil)
	}

	public func stopObservingBatchChanges(from other: NSManagedObjectContext) {
		let defaultCenter = NSNotificationCenter.defaultCenter()

		defaultCenter.removeObserver(self,
		                             name: didBatchDeleteNotification,
		                             object: nil)

		defaultCenter.removeObserver(self,
		                             name: didBatchUpdateNotification,
		                             object: nil)
	}

	public func schedule(block: () -> Void) {
		if concurrencyType == .MainQueueConcurrencyType && NSThread.isMainThread() {
			block()
		} else {
			performBlock(block)
		}
	}

	public func prepare<Result>(@noescape block: () -> Result) -> Result {
		if concurrencyType == .MainQueueConcurrencyType && NSThread.isMainThread() {
			return block()
		} else {
			var returnResult: Result!
			performBlockAndWaitNoEscape {
				returnResult = block()
			}
			return returnResult
		}
	}

	public func perform(@noescape block: () -> Void) {
		if concurrencyType == .MainQueueConcurrencyType && NSThread.isMainThread() {
			block()
		} else {
			performBlockAndWaitNoEscape(block)
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

		NSNotificationCenter.defaultCenter()
			.postNotificationName(didBatchUpdateNotification,
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: objectIDs])
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

		NSNotificationCenter.defaultCenter()
			.postNotificationName(didBatchDeleteNotification,
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: objectIDs])
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
				guard let resultIDs = notification.userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
					return
				}

				self.deleteObjectsWith(resultIDs)
			}
		}
	}

	@objc public func handleExternalBatchUpdate(notification: NSNotification) {
		if let context = notification.object as? NSManagedObjectContext where self.isSiblingOf(context) {
			performBlock {
				guard let resultIDs = notification.userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
					return
				}

				self.updateObjectsWith(resultIDs)
			}
		}
	}
}