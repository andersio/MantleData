import Nimble
import XCTest
import Foundation
import ReactiveSwift
import ReactiveCocoa
import MantleData
import CoreData

class Receiver: NSObject, NSFetchedResultsControllerDelegate {
	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {

	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {

	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

	}
}

class ObjectCollectionTests: XCTestCase {
	var directoryUrl: URL!
	var storeCoordinator: NSPersistentStoreCoordinator!
	var mainContext: NSManagedObjectContext!

	func testOCInsertionPerformance_10000_iterations() {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		expect { try collection.fetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 10000 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testOCInsertionPerformance_2000_iterations() {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		expect { try collection.fetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 2000 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testOCInsertionPerformance_1000_iterations() {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		expect { try collection.fetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 1000 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testOCInsertionPerformance_100_iterations() {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		expect { try collection.fetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 100 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testOCInsertionPerformance_10_iterations() {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		expect { try collection.fetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 10 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testFRCInsertionPerformance_2000_iterations() {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver
		expect { try controller.performFetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 2000 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testFRCInsertionPerformance_1000_iterations() {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver
		expect { try controller.performFetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 1000 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testFRCInsertionPerformance_100_iterations() {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver
		expect { try controller.performFetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 100 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	func testFRCInsertionPerformance_10_iterations() {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver
		expect { try controller.performFetch() }.toNot(throwError())

		measure {
			for i in 0 ..< 10 {
				let children = Children(context: self.mainContext)
				children.value = "\(i)"
			}

			self.mainContext.processPendingChanges()
			self.mainContext.reset()
		}
	}

	override func setUp() {
		let url = Bundle(for: ObjectCollectionTests.self).url(forResource: "Model", withExtension: "momd")!
		let model = NSManagedObjectModel(contentsOf: url)!

		directoryUrl = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString,
			                        isDirectory: true)

		try! FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true, attributes: nil)

		let storeUrl = directoryUrl.appendingPathComponent("store.sqlite3")
		let storeDescription = NSPersistentStoreDescription(url: storeUrl)
		storeDescription.shouldAddStoreAsynchronously = false
		storeDescription.type = NSSQLiteStoreType

		storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
		storeCoordinator.addPersistentStore(with: storeDescription) { _, error in
			expect(error).to(beNil())
		}

		mainContext = NSManagedObjectContext(parent: .persistentStore(storeCoordinator),
		                                         concurrencyType: .mainQueueConcurrencyType)
	}

	override func tearDown() {
		try! storeCoordinator.remove(storeCoordinator.persistentStores[0])
		try! FileManager.default.removeItem(at: directoryUrl)
	}
}
