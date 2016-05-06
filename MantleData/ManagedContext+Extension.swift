//
//  ManagedContext+Extension.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import CoreData

public let objectContextWillMergeChangesNotification = "MDContextWillMergeChangesNotification"

private let didBatchUpdateNotification = "MDDidBatchUpdate"
private let willBatchDeleteNotification = "MDWillBatchDelete"
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
			             object: other)
	}

	public func stopObservingSavedChanges(from other: NSManagedObjectContext) {
		NSNotificationCenter.defaultCenter()
			.removeObserver(self,
			                name: NSManagedObjectContextDidSaveNotification,
			                object: other)
	}

	public func observeBatchChanges(from other: NSManagedObjectContext) {
		let defaultCenter = NSNotificationCenter.defaultCenter()

		defaultCenter.addObserver(self,
		                          selector: #selector(NSManagedObjectContext.handleExternalBatchUpdate(_:)),
		                          name: didBatchUpdateNotification,
		                          object: other)

		defaultCenter.addObserver(self,
		                          selector: #selector(NSManagedObjectContext.preprocessBatchDelete(_:)),
		                          name: willBatchDeleteNotification,
		                          object: other)
	}

	public func stopObservingBatchChanges(from other: NSManagedObjectContext) {
		let defaultCenter = NSNotificationCenter.defaultCenter()

		defaultCenter.removeObserver(self,
		                             name: willBatchDeleteNotification,
		                             object: other)

		defaultCenter.removeObserver(self,
		                             name: didBatchUpdateNotification,
		                             object: other)
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
		let IDRequest = request.fetchRequest.copy() as! NSFetchRequest
		IDRequest.resultType = .ManagedObjectIDResultType
		IDRequest.includesPropertyValues = false
		IDRequest.includesPendingChanges = false

		guard let affectingObjectIDs = try executeFetchRequest(IDRequest) as? [NSManagedObjectID] else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the affecting ID array for a batch delete request.")
		}

		deleteObjects(with: affectingObjectIDs)

		NSNotificationCenter.defaultCenter()
			.postNotificationName(willBatchDeleteNotification,
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: affectingObjectIDs])

		request.resultType = .ResultTypeCount

		guard let requestResult = try self.executeRequest(request) as? NSBatchDeleteResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let count = requestResult.result as? NSNumber else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result count for a batch delete request.")
		}

		precondition(count.integerValue == affectingObjectIDs.count)

		NSNotificationCenter.defaultCenter()
			.postNotificationName(didBatchDeleteNotification,
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: affectingObjectIDs])

	}

	private func deleteObjects(with resultIDs: [NSManagedObjectID]) {
		for ID in resultIDs {
			deleteObject(objectWithID(ID))
		}

		processPendingChanges()
	}

	private func updateObjectsWith(resultIDs: [NSManagedObjectID]) {
		// Force the context to discard the cached data.
		// breaks infinite staleness guarantee??
		let objects = resultIDs.flatMap { objectRegisteredForID($0) }

		NSNotificationCenter.defaultCenter()
			.postNotificationName(objectContextWillMergeChangesNotification,
			                      object: self,
			                      userInfo: nil)

		let previousInterval = stalenessInterval
		stalenessInterval = 0

		objects.forEach { refreshObject($0, mergeChanges: true) }

		stalenessInterval = previousInterval
	}

	private func isSourcedFromIdenticalPersistentStoreCoordinator(as other: NSManagedObjectContext, inout localCoordinator: NSPersistentStoreCoordinator?) -> Bool {
		guard other !== self else {
			return true
		}

		var _selfCoordinator = persistentStoreCoordinator
		var iterator = Optional(self)

		while _selfCoordinator == nil && iterator?.parentContext != nil {
			iterator = iterator!.parentContext
			_selfCoordinator = iterator?.persistentStoreCoordinator
		}

		guard let selfCoordinator = _selfCoordinator else {
			preconditionFailure("The tree of contexts have no persistent store coordinator presented at the root.")
		}

		var _remoteCoordinator = persistentStoreCoordinator
		iterator = Optional(other)

		while _remoteCoordinator == nil && iterator?.parentContext != nil {
			iterator = iterator!.parentContext
			_remoteCoordinator = iterator?.persistentStoreCoordinator
		}

		guard let remoteCoordinator = _remoteCoordinator else {
			preconditionFailure("The tree of contexts have no persistent store coordinator presented at the root.")
		}

		localCoordinator = selfCoordinator
		return remoteCoordinator === selfCoordinator
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
		guard let userInfo = notification.userInfo else {
			return
		}

		let context = notification.object as! NSManagedObjectContext
		var localCoordinator: NSPersistentStoreCoordinator?
		let hasIdenticalSource = isSourcedFromIdenticalPersistentStoreCoordinator(as: context,
		                                                                          localCoordinator: &localCoordinator)

		perform {
			NSNotificationCenter.defaultCenter()
				.postNotificationName(objectContextWillMergeChangesNotification,
					object: self,
					userInfo: nil)

			if hasIdenticalSource {
				mergeChangesFromContextDidSaveNotification(notification)
			} else {
				NSManagedObjectContext.mergeChangesFromRemoteContextSave(userInfo,
					intoContexts: [self])
			}
		}
	}

	@objc private func preprocessBatchDelete(notification: NSNotification) {
		perform {
			guard let resultIDs = notification.userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}

			self.deleteObjects(with: resultIDs)
		}
	}

	@objc private func handleExternalBatchUpdate(notification: NSNotification) {
		perform {
			guard let resultIDs = notification.userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}
			
			self.updateObjectsWith(resultIDs)
		}
	}
}