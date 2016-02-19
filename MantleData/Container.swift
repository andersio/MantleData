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
final public class Container: Base {
	public let url: NSURL
	public let model: NSManagedObjectModel
	public let modelConfiguration: String?

	public let mainContext: ObjectContext
	public let rootSavingContext: ObjectContext

	internal let persistentStoreCoordinator: NSPersistentStoreCoordinator

	private var _isSaving = MutableProperty<UInt>(0)
	private(set) public lazy var isSaving: AnyProperty<Bool> = { [unowned self] in
		return AnyProperty<Bool>(initialValue: false,
			producer: self._isSaving.producer
				.map { $0 != 0 }
				.skipRepeats())
	}()


	public init(url: NSURL, model: NSManagedObjectModel, modelConfiguration: String? = nil) {
		self.url = url
		self.model = model
		self.modelConfiguration = modelConfiguration

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		self.persistentStoreCoordinator = coordinator

		if url.pathExtension != "mdcontainer" {
			fatalError("You must open a MantleData container.")
		}

		let fileManager = NSFileManager.defaultManager()
		if !fileManager.fileExistsAtPath(url.path!) {
			do {
				try fileManager.createDirectoryAtURL(url, withIntermediateDirectories: false, attributes: nil)
			} catch let error as NSError {
				fatalError("Failed to create the container. Message: \(error.description)")
			}
		}

		if let modelConfiguration = modelConfiguration where !model.configurations.contains(modelConfiguration) {
			fatalError("The managed object model does not contain the specified configuration.")
		}

		let storeURL = url.URLByAppendingPathComponent("Database.sqlite3")

    do {
      try persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType,
				configuration: modelConfiguration,
				URL: storeURL,
				options: nil)
    } catch _ as NSError {
      try! NSFileManager.defaultManager().removeItemAtURL(storeURL)
			NSLog("SQLite store deleted.")

      try! persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType,
				configuration: modelConfiguration,
				URL: storeURL,
				options: nil)
    }

		rootSavingContext = ObjectContext(parent: .PersistentStore(persistentStoreCoordinator),
		                            concurrencyType: .MainQueueConcurrencyType,
		                            mergePolicy: MergePolicy.RaiseError.cocoaValue)

		mainContext = ObjectContext(parent: .Context(rootSavingContext),
		                            concurrencyType: .MainQueueConcurrencyType,
		                            mergePolicy: MergePolicy.RaiseError.cocoaValue)

		super.init()

		observeSavingNotificationsOf(rootSavingContext)
		observeSavingNotificationsOf(mainContext)
	}

	public func prepare<Result>(@noescape action: ObjectContext -> Result) -> Result {
		return mainContext.prepare { action(mainContext) }
	}

	public func save(action: ObjectContext -> Void) -> SignalProducer<Void, NSError> {
		let (producer, observer) = SignalProducer<Void, NSError>.buffer(0)

		rootSavingContext.perform {
			action(rootSavingContext)
			do {
				try rootSavingContext.save()
				observer.sendCompleted()
			} catch let e as NSError {
				observer.sendFailed(e)
			}
		}

		return producer
	}

  public func privateQueueRootContext(mergePolicy: MergePolicy = .PreferMemoryWhenMerging) -> ObjectContext {
    let context = ObjectContext(parent: .PersistentStore(persistentStoreCoordinator),
			concurrencyType: .PrivateQueueConcurrencyType,
			mergePolicy: mergePolicy.cocoaValue)
		observeSavingNotificationsOf(context)

    return context
  }

	public func mainQueueRootContext(mergePolicy: MergePolicy = .PreferMemoryWhenMerging) -> ObjectContext {
		let context = ObjectContext(parent: .PersistentStore(persistentStoreCoordinator),
			concurrencyType: .MainQueueConcurrencyType,
			mergePolicy: mergePolicy.cocoaValue)
		observeSavingNotificationsOf(context)

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
}

public enum MergePolicy {
	case Custom(NSMergePolicy)
  case PreferMemoryWhenMerging
  case PreferStoreWhenMerging
  case OverwriteStore
  case RollbackToStore
  case RaiseError

  private var cocoaValue: AnyObject {
    switch self {
    case .PreferMemoryWhenMerging:  return NSMergeByPropertyObjectTrumpMergePolicy
    case .PreferStoreWhenMerging:   return NSMergeByPropertyStoreTrumpMergePolicy
    case .RaiseError:         return NSErrorMergePolicy
    case .OverwriteStore:     return NSOverwriteMergePolicy
    case .RollbackToStore:    return NSRollbackMergePolicy
		case let .Custom(mergePolicy): return mergePolicy
    }
  }
}

public enum Concurrency {
  case MainQueue
  case PrivateQueue
  
  private var cocoaValue: NSManagedObjectContextConcurrencyType {
    switch self {
    case .MainQueue:    return .MainQueueConcurrencyType
    case .PrivateQueue: return .PrivateQueueConcurrencyType
    }
  }
}