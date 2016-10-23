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

@nonobjc let batchRequestResultIDArrayKey = Notification.Name(rawValue: "MDResultIDs")

extension Notification.Name {
	@nonobjc public static let objectContextWillMergeChanges = Notification.Name(rawValue: "MDContextWillMergeChangesNotification")

	@nonobjc static let didBatchUpdate = Notification.Name(rawValue: "MDDidBatchUpdate")
	@nonobjc static let willBatchDelete = Notification.Name(rawValue: "MDWillBatchDelete")
	@nonobjc static let didBatchDelete = Notification.Name(rawValue: "MDDidBatchDelete")
}

extension NSManagedObjectContext {
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
}

extension Reactive where Base: NSManagedObjectContext {
	public func objects<E: NSManagedObject>(_ type: E.Type) -> ObjectQuery<E> {
		return ObjectQuery(in: base)
	}

	public func fetch<E: NSManagedObject>(_ id: ManagedObjectID<E>, in context: NSManagedObjectContext) throws -> E {
		return try context.existingObject(with: id.id) as! E
	}

	@discardableResult
	public func observeSavedChanges(from other: NSManagedObjectContext) -> Disposable? {
		return NotificationCenter.default.reactive
			.notifications(forName: .NSManagedObjectContextDidSave, object: other)
			.take(until: lifetime.ended.zip(with: other.reactive.lifetime.ended).map { _ in })
			.observeValues(handleExternalChanges(_:))
	}

	@discardableResult
	public func observeBatchChanges(from other: NSManagedObjectContext) -> Disposable {
		let disposable = CompositeDisposable()
		let defaultCenter = NotificationCenter.default

		disposable += defaultCenter.reactive
			.notifications(forName: .didBatchUpdate, object: other)
			.take(until: lifetime.ended.zip(with: other.reactive.lifetime.ended).map { _ in })
			.observeValues(handleExternalBatchUpdate(_:))

		disposable += defaultCenter.reactive
			.notifications(forName: .willBatchDelete, object: other)
			.take(until: lifetime.ended.zip(with: other.reactive.lifetime.ended).map { _ in })
			.observeValues(preprocessBatchDelete(_:))

		return disposable
	}


	/// Batch update objects, and update other contexts asynchronously.
	public func batchUpdate(_ request: NSBatchUpdateRequest) throws {
		request.resultType = .updatedObjectIDsResultType

		guard let requestResult = try base.execute(request) as? NSBatchUpdateResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let objectIDs = requestResult.result as? [NSManagedObjectID] else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result ID array for a batch update request.")
		}

		updateObjectsWith(objectIDs)

		NotificationCenter.default
			.post(name: .didBatchUpdate,
			      object: base,
						userInfo: [batchRequestResultIDArrayKey: objectIDs])
	}

	/// Batch delete objects, and update other contexts asynchronously.
	@available(iOS 9.0, macOS 10.11, *)
	public func batchDelete(_ request: NSBatchDeleteRequest) throws {
		let IDRequest = request.fetchRequest.copy() as! NSFetchRequest<NSManagedObjectID>
		IDRequest.resultType = .managedObjectIDResultType
		IDRequest.includesPropertyValues = false
		IDRequest.includesPendingChanges = false

		guard let affectingObjectIDs = try? base.fetch(IDRequest) else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the affecting ID array for a batch delete request.")
		}

		deleteObjects(with: affectingObjectIDs)

		NotificationCenter.default
			.post(name: .willBatchDelete,
			      object: base,
			      userInfo: [batchRequestResultIDArrayKey: affectingObjectIDs])

		request.resultType = .resultTypeCount

		guard let requestResult = try base.execute(request) as? NSBatchDeleteResult else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result object from the object context.")
		}

		guard let count = requestResult.result as? NSNumber else {
			fatalError("StoreCoordinator.performBatchRequest: Cannot obtain the result count for a batch delete request.")
		}

		precondition(count.intValue == affectingObjectIDs.count)

		NotificationCenter.default
			.post(name: .didBatchDelete,
			      object: base,
			      userInfo: [batchRequestResultIDArrayKey: affectingObjectIDs])

	}

	private func deleteObjects(with resultIDs: [NSManagedObjectID]) {
		for ID in resultIDs {
			base.delete(base.object(with: ID))
		}

		base.processPendingChanges()
	}

	private func updateObjectsWith(_ resultIDs: [NSManagedObjectID]) {
		// Force the context to discard the cached data.
		// breaks infinite staleness guarantee??
		let objects = resultIDs.flatMap { base.registeredObject(for: $0) }

		NotificationCenter.default
			.post(name: .objectContextWillMergeChanges,
			                      object: base,
			                      userInfo: nil)

		let previousInterval = base.stalenessInterval
		base.stalenessInterval = 0

		objects.forEach { base.refresh($0, mergeChanges: true) }

		base.stalenessInterval = previousInterval
	}

	private func isSourcedFromIdenticalPersistentStoreCoordinator(as other: NSManagedObjectContext, localCoordinator: inout NSPersistentStoreCoordinator?) -> Bool {
		guard other !== base else {
			return true
		}

		var _baseCoordinator = base.persistentStoreCoordinator
		var iterator = Optional(base as NSManagedObjectContext)

		while _baseCoordinator == nil && iterator?.parent != nil {
			iterator = iterator!.parent
			_baseCoordinator = iterator?.persistentStoreCoordinator
		}

		guard let baseCoordinator = _baseCoordinator else {
			preconditionFailure("The tree of contexts have no persistent store coordinator presented at the root.")
		}

		var _remoteCoordinator = base.persistentStoreCoordinator
		iterator = Optional(other)

		while _remoteCoordinator == nil && iterator?.parent != nil {
			iterator = iterator!.parent
			_remoteCoordinator = iterator?.persistentStoreCoordinator
		}

		guard let remoteCoordinator = _remoteCoordinator else {
			preconditionFailure("The tree of contexts have no persistent store coordinator presented at the root.")
		}

		localCoordinator = baseCoordinator
		return remoteCoordinator === baseCoordinator
	}

	private func isSiblingOf(_ other: NSManagedObjectContext) -> Bool {
		if other !== base {
			// Fast Paths
			if let persistentStoreCoordinator = base.persistentStoreCoordinator, persistentStoreCoordinator == other.persistentStoreCoordinator {
				return true
			}

			if let parentContext = base.parent, parentContext == other.parent {
				return true
			}

			// Slow Path
			var myPSC = base.persistentStoreCoordinator
			var otherPSC = other.persistentStoreCoordinator
			var myContext: NSManagedObjectContext = base
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

	public func handleExternalChanges(_ notification: Notification) {
		guard let userInfo = (notification as NSNotification).userInfo else {
			return
		}

		let context = notification.object as! NSManagedObjectContext
		var localCoordinator: NSPersistentStoreCoordinator?
		let hasIdenticalSource = isSourcedFromIdenticalPersistentStoreCoordinator(as: context,
		                                                                          localCoordinator: &localCoordinator)

		base.sync {
			NotificationCenter.default
				.post(name: .objectContextWillMergeChanges,
					object: base,
					userInfo: nil)

			if #available(iOS 9.0, macOS 10.11, *), !hasIdenticalSource {
				NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo,
																						into: [base])
			} else {
				base.mergeChanges(fromContextDidSave: notification)
			}
		}
	}

	private func preprocessBatchDelete(_ notification: Notification) {
		base.sync {
			guard let resultIDs = (notification as NSNotification).userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}

			deleteObjects(with: resultIDs)
		}
	}

	private func handleExternalBatchUpdate(_ notification: Notification) {
		base.sync {
			guard let resultIDs = (notification as NSNotification).userInfo?[batchRequestResultIDArrayKey] as? [NSManagedObjectID] else {
				return
			}
			
			updateObjectsWith(resultIDs)
		}
	}
}
