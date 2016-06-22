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
			self.parent = context
		}
	}

	public func observeSavedChanges(from other: NSManagedObjectContext) {
		NotificationCenter.default()
			.addObserver(self,
			             selector: #selector(NSManagedObjectContext.handleExternalChanges(_:)),
			             name: NSNotification.Name.NSManagedObjectContextDidSave,
			             object: other)
	}

	public func stopObservingSavedChanges(from other: NSManagedObjectContext) {
		NotificationCenter.default()
			.removeObserver(self,
			                name: NSNotification.Name.NSManagedObjectContextDidSave,
			                object: other)
	}

	public func observeBatchChanges(from other: NSManagedObjectContext) {
		let defaultCenter = NotificationCenter.default()

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
		let defaultCenter = NotificationCenter.default()

		defaultCenter.removeObserver(self,
		                             name: NSNotification.Name(rawValue: willBatchDeleteNotification),
		                             object: other)

		defaultCenter.removeObserver(self,
		                             name: NSNotification.Name(rawValue: didBatchUpdateNotification),
		                             object: other)
	}

	/// Enqueue a block to the context.
	public func async(_ block: () -> Void) {
		perform(block)
	}

	/// Execute a block on the context, and propagate the returned result.
	/// - Important: The call is pre-emptive and jumps the context's internal queue.
	public func sync<Result>(_ block: @noescape () -> Result) -> Result {
		var returnResult: Result!
		performBlockAndWaitNoEscape { returnResult = block() }
		return returnResult
	}

	/// Batch update objects, and update other contexts asynchronously.
	public func batchUpdate(_ request: NSBatchUpdateRequest) throws {
		request.resultType = .updatedObjectIDsResultType

		guard let requestResult = try self.execute(request) as? NSBatchUpdateResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let objectIDs = requestResult.result as? [NSManagedObjectID] else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result ID array for a batch update request.")
		}

		updateObjectsWith(objectIDs)

		NotificationCenter.default()
			.post(name: Notification.Name(rawValue: didBatchUpdateNotification),
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: objectIDs])
	}

	/// Batch delete objects, and update other contexts asynchronously.
	public func batchDelete(_ request: NSBatchDeleteRequest) throws {
		let IDRequest = request.fetchRequest.copy() as! NSFetchRequest<NSManagedObjectID>
		IDRequest.resultType = .managedObjectIDResultType
		IDRequest.includesPropertyValues = false
		IDRequest.includesPendingChanges = false

		guard let affectingObjectIDs = try? fetch(IDRequest) else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the affecting ID array for a batch delete request.")
		}

		deleteObjects(with: affectingObjectIDs)

		NotificationCenter.default()
			.post(name: Notification.Name(rawValue: willBatchDeleteNotification),
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: affectingObjectIDs])

		request.resultType = .resultTypeCount

		guard let requestResult = try self.execute(request) as? NSBatchDeleteResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let count = requestResult.result as? NSNumber else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result count for a batch delete request.")
		}

		precondition(count.intValue == affectingObjectIDs.count)

		NotificationCenter.default()
			.post(name: Notification.Name(rawValue: didBatchDeleteNotification),
			                      object: self,
			                      userInfo: [batchRequestResultIDArrayKey: affectingObjectIDs])

	}

	private func deleteObjects(with resultIDs: [NSManagedObjectID]) {
		for ID in resultIDs {
			delete(object(with: ID))
		}

		processPendingChanges()
	}

	private func updateObjectsWith(_ resultIDs: [NSManagedObjectID]) {
		// Force the context to discard the cached data.
		// breaks infinite staleness guarantee??
		let objects = resultIDs.flatMap { registeredObject(for: $0) }

		NotificationCenter.default()
			.post(name: Notification.Name(rawValue: objectContextWillMergeChangesNotification),
			                      object: self,
			                      userInfo: nil)

		let previousInterval = stalenessInterval
		stalenessInterval = 0

		objects.forEach { refresh($0, mergeChanges: true) }

		stalenessInterval = previousInterval
	}

	private func isSourcedFromIdenticalPersistentStoreCoordinator(as other: NSManagedObjectContext, localCoordinator: inout NSPersistentStoreCoordinator?) -> Bool {
		guard other !== self else {
			return true
		}

		var _selfCoordinator = persistentStoreCoordinator
		var iterator = Optional(self)

		while _selfCoordinator == nil && iterator?.parent != nil {
			iterator = iterator!.parent
			_selfCoordinator = iterator?.persistentStoreCoordinator
		}

		guard let selfCoordinator = _selfCoordinator else {
			preconditionFailure("The tree of contexts have no persistent store coordinator presented at the root.")
		}

		var _remoteCoordinator = persistentStoreCoordinator
		iterator = Optional(other)

		while _remoteCoordinator == nil && iterator?.parent != nil {
			iterator = iterator!.parent
			_remoteCoordinator = iterator?.persistentStoreCoordinator
		}

		guard let remoteCoordinator = _remoteCoordinator else {
			preconditionFailure("The tree of contexts have no persistent store coordinator presented at the root.")
		}

		localCoordinator = selfCoordinator
		return remoteCoordinator === selfCoordinator
	}

	private func isSiblingOf(_ other: NSManagedObjectContext) -> Bool {
		if other !== self {
			// Fast Paths
			if let persistentStoreCoordinator = persistentStoreCoordinator
				where persistentStoreCoordinator == other.persistentStoreCoordinator {
				return true
			}

			if let parentContext = parent where parentContext == other.parent {
				return true
			}

			// Slow Path
			var myPSC = persistentStoreCoordinator
			var otherPSC = other.persistentStoreCoordinator
			var myContext: NSManagedObjectContext = self
			var otherContext: NSManagedObjectContext = other

			while let parent = myContext.parent {
				myContext = parent
				myPSC = myContext.persistentStoreCoordinator
			}

			while let parent = otherContext.parent {
				otherContext = parent
				otherPSC = otherContext.persistentStoreCoordinator
			}

			if myPSC == otherPSC {
				return true
			}
		}

		return false
	}

	@objc public func handleExternalChanges(_ notification: Notification) {
		guard let userInfo = (notification as NSNotification).userInfo else {
			return
		}

		let context = notification.object as! NSManagedObjectContext
		var localCoordinator: NSPersistentStoreCoordinator?
		let hasIdenticalSource = isSourcedFromIdenticalPersistentStoreCoordinator(as: context,
		                                                                          localCoordinator: &localCoordinator)

		sync {
			NotificationCenter.default()
				.post(name: Notification.Name(rawValue: objectContextWillMergeChangesNotification),
					object: self,
					userInfo: nil)

			if hasIdenticalSource {
				self.mergeChanges(fromContextDidSave: notification)
			} else {
				NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo,
					into: [self])
			}
		}
	}

	@objc private func preprocessBatchDelete(_ notification: Notification) {
		sync {
			guard let resultIDs = (notification as NSNotification).userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}

			self.deleteObjects(with: resultIDs)
		}
	}

	@objc private func handleExternalBatchUpdate(_ notification: Notification) {
		sync {
			guard let resultIDs = (notification as NSNotification).userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}
			
			self.updateObjectsWith(resultIDs)
		}
	}
}
