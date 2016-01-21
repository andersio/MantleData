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

	internal let persistentStoreCoordinator: NSPersistentStoreCoordinator

	private(set) public lazy var mainContext: ObjectContext = { [unowned self] in
		return self.mainQueueContext(.PreferStoreWhenMerging)
	}()

	private(set) public lazy var writeContext: ObjectContext = { [unowned self] in
		return self.privateQueueContext(.PreferMemoryWhenMerging)
	}()

	private(set) public lazy var isSaving: AnyProperty<Bool> = { [unowned self] in
		return AnyProperty<Bool>(initialValue: false,
			producer: self._isSaving.producer
				.map { $0 != 0 }
				.skipRepeats())
	}()

	private var _isSaving = MutableProperty<UInt>(0)

	private var storeURL: NSURL {
		return url.URLByAppendingPathComponent("Database.sqlite3")
	}

	public init(url: NSURL, model: NSManagedObjectModel, modelConfiguration: String? = nil) {
		self.url = url
		self.model = model
		self.modelConfiguration = modelConfiguration

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		self.persistentStoreCoordinator = coordinator

		super.init()

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

    do {
      try persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType,
				configuration: modelConfiguration,
				URL: storeURL,
				options: nil)
    } catch _ as NSError {
      try! NSFileManager.defaultManager().removeItemAtURL(url)
			NSLog("SQLite store deleted.")

      try! persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType,
				configuration: modelConfiguration,
				URL: storeURL,
				options: nil)
    }
	}

  public func privateQueueContext(mergePolicy: MergePolicy = .PreferMemoryWhenMerging) -> ObjectContext {
    let context = ObjectContext(persistentStoreCoordinator: persistentStoreCoordinator,
			concurrencyType: .PrivateQueueConcurrencyType,
			mergePolicy: mergePolicy.cocoaValue)
		observeSavingNotificationsOf(context)

    return context
  }

	public func mainQueueContext(mergePolicy: MergePolicy = .PreferMemoryWhenMerging) -> ObjectContext {
		let context = ObjectContext(persistentStoreCoordinator: persistentStoreCoordinator,
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