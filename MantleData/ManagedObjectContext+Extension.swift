//
//  ManagedContext+Extension.swift
//  MantleData
//
//  Created by Anders on 11/10/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

import Foundation
import CoreData
import ReactiveSwift
import ReactiveCocoa

extension Notification.Name {
	@nonobjc public static let objectContextWillMergeChanges = Notification.Name(rawValue: "MDContextWillMergeChangesNotification")

	@nonobjc static let didBatchUpdate = Notification.Name(rawValue: "MDDidBatchUpdate")
	@nonobjc static let willBatchDelete = Notification.Name(rawValue: "MDWillBatchDelete")
	@nonobjc static let didBatchDelete = Notification.Name(rawValue: "MDDidBatchDelete")
}

extension NSManagedObjectContext {
	@nonobjc static let batchRequestResultIDArrayKey = Notification.Name(rawValue: "MDResultIDs")

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

	@discardableResult
	public func observeSavedChanges(from other: NSManagedObjectContext) -> Disposable {
		return NotificationCenter.default
			.rac_notifications(forName: .NSManagedObjectContextDidSave, object: other)
			.take(until: rac.lifetime.ended.zip(with: other.rac.lifetime.ended).map { _ in })
			.startWithValues(handleExternalChanges(_:))
	}

	@discardableResult
	public func observeBatchChanges(from other: NSManagedObjectContext) -> Disposable {
		let disposable = CompositeDisposable()
		let defaultCenter = NotificationCenter.default

		disposable += defaultCenter
			.rac_notifications(forName: .didBatchUpdate, object: other)
			.take(until: rac.lifetime.ended.zip(with: other.rac.lifetime.ended).map { _ in })
			.startWithValues(handleExternalBatchUpdate(_:))

		disposable += defaultCenter
			.rac_notifications(forName: .willBatchDelete, object: other)
			.take(until: rac.lifetime.ended.zip(with: other.rac.lifetime.ended).map { _ in })
			.startWithValues(preprocessBatchDelete(_:))

		return disposable
	}

	/// Enqueue a block to the context.
	public func async(_ block: @escaping () -> Void) {
		perform(block)
	}

	/// Execute a block on the context, and propagate the returned result.
	/// - Important: The call is pre-emptive and jumps the context's internal queue.
	public func sync<Result>(_ block: () -> Result) -> Result {
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

		NotificationCenter.default
			.post(name: .didBatchUpdate,
			      object: self,
						userInfo: [NSManagedObjectContext.batchRequestResultIDArrayKey: objectIDs])
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

		NotificationCenter.default
			.post(name: .willBatchDelete,
			      object: self,
			      userInfo: [NSManagedObjectContext.batchRequestResultIDArrayKey: affectingObjectIDs])

		request.resultType = .resultTypeCount

		guard let requestResult = try self.execute(request) as? NSBatchDeleteResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let count = requestResult.result as? NSNumber else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result count for a batch delete request.")
		}

		precondition(count.intValue == affectingObjectIDs.count)

		NotificationCenter.default
			.post(name: .didBatchDelete,
			      object: self,
			      userInfo: [NSManagedObjectContext.batchRequestResultIDArrayKey: affectingObjectIDs])

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

		NotificationCenter.default
			.post(name: .objectContextWillMergeChanges,
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
			if let persistentStoreCoordinator = persistentStoreCoordinator, persistentStoreCoordinator == other.persistentStoreCoordinator {
				return true
			}

			if let parentContext = parent, parentContext == other.parent {
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
			NotificationCenter.default
				.post(name: .objectContextWillMergeChanges,
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
			guard let resultIDs = (notification as NSNotification).userInfo?[NSManagedObjectContext.batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}

			self.deleteObjects(with: resultIDs)
		}
	}

	@objc private func handleExternalBatchUpdate(_ notification: Notification) {
		sync {
			guard let resultIDs = (notification as NSNotification).userInfo?[NSManagedObjectContext.batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}
			
			self.updateObjectsWith(resultIDs)
		}
	}
}
