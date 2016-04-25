//
//  DataStore
//  Galleon
//
//  Created by Ik ben anders on 11/8/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import ReactiveCocoa
import CoreData

/// Container manages a Core Data persistent store and coordinates between requested object contexts.
final public class Container {
	public let url: NSURL
	public let model: NSManagedObjectModel
	public let modelConfiguration: String?

	public let mainContext: ObjectContext
	public let rootSavingContext: ObjectContext
	internal let mergePolicy: ObjectMergePolicy

	internal let persistentStoreCoordinator: NSPersistentStoreCoordinator

	private var _isSaving = MutableProperty<UInt>(0)
	private(set) public lazy var isSaving: AnyProperty<Bool> = { [unowned self] in
		return AnyProperty<Bool>(initialValue: false,
			producer: self._isSaving.producer
				.map { $0 != 0 }
				.skipRepeats())
	}()

	public init(url: NSURL, model: NSManagedObjectModel, modelConfiguration: String? = nil) throws {
		self.url = url
		self.model = model
		self.modelConfiguration = modelConfiguration

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		self.persistentStoreCoordinator = coordinator

		if url.pathExtension != "mdcontainer" {
			throw Error.InvalidFileExtension
		}

		let fileManager = NSFileManager.defaultManager()
		if !fileManager.fileExistsAtPath(url.path!) {
			do {
				try fileManager.createDirectoryAtURL(url, withIntermediateDirectories: false, attributes: nil)
			} catch let error as NSError {
				throw Error.CannotCreateContainer(error)
			}
		}

		if let modelConfiguration = modelConfiguration where !model.configurations.contains(modelConfiguration) {
			throw Error.ModelConfigurationNotFound
		}

		let storeURL = url.URLByAppendingPathComponent("Database.sqlite3")

		do {
			try persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType,
			                                                          configuration: modelConfiguration,
			                                                          URL: storeURL,
			                                                          options: nil)
		} catch let error as NSError {
			throw Error.CannotAddPersistentStore(error)
		}

		mergePolicy = ObjectMergePolicy.make()
		rootSavingContext = ObjectContext(parent: .PersistentStore(persistentStoreCoordinator),
		                                  concurrencyType: .PrivateQueueConcurrencyType)

		mainContext = ObjectContext(parent: .PersistentStore(persistentStoreCoordinator),
		                            concurrencyType: .MainQueueConcurrencyType)

		observeSavingNotificationsOf(rootSavingContext)
		rootSavingContext.mergePolicy = mergePolicy

		observeSavingNotificationsOf(mainContext)
		mainContext.mergePolicy = NSRollbackMergePolicy
	}

	public func resetMergePolicy(for context: ObjectContext) {
		assert(context.persistentStoreCoordinator == persistentStoreCoordinator)
		context.mergePolicy = mergePolicy
	}

	public func prepareOnMainThread<Result>(@noescape action: ObjectContext -> Result) -> Result {
		return mainContext.prepare { action(mainContext) }
	}

	public func saveInBackground(action: ObjectContext -> Void) -> SignalProducer<Void, NSError> {
		let (producer, observer) = SignalProducer<Void, NSError>.buffer(0)

		rootSavingContext.schedule {
			action(self.rootSavingContext)
			do {
				try self.rootSavingContext.save()
				observer.sendCompleted()
			} catch let e as NSError {
				observer.sendFailed(e)
			}
		}

		return producer
	}

	public func makeContext(for concurrencyType: NSManagedObjectContextConcurrencyType) -> ObjectContext {
    let context = ObjectContext(parent: .PersistentStore(persistentStoreCoordinator),
			concurrencyType: concurrencyType)
		observeSavingNotificationsOf(context)
		context.mergePolicy = mergePolicy

    return context
  }

	private func observeSavingNotificationsOf<C: NSManagedObjectContext>(context: C) {
		let center = NSNotificationCenter.defaultCenter()

		center.rac_notifications(NSManagedObjectContextWillSaveNotification,
			object: context)
			.takeUntil(context.willDeinitProducer)
			.startWithNext { _ in
				self._isSaving.modify { $0 + 1 }
			}

		center.rac_notifications(NSManagedObjectContextDidSaveNotification,
			object: context)
			.takeUntil(context.willDeinitProducer)
			.startWithNext { _ in
				self._isSaving.modify { $0 - 1 }
		}
	}

	// Container Error
	public enum Error: ErrorType {
		case InvalidFileExtension
		case CannotCreateContainer(NSError)
		case ModelConfigurationNotFound
		case CannotAddPersistentStore(NSError)
	}
}