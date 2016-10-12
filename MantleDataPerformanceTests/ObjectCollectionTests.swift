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

	func measureOCDeletionPerformance(times: Int) {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		measure {
			var children = [Children]()
			children.reserveCapacity(times)

			for i in 0 ..< times {
				let child = Children(context: self.mainContext)
				child.value = Int64(i)
				children.append(child)
			}

			self.mainContext.processPendingChanges()

			expect { try collection.fetch() }.toNot(throwError())
			expect(collection.count) == times

			children.forEach(self.mainContext.delete)
			self.mainContext.processPendingChanges()

			expect(collection.count) == 0
			self.mainContext.reset()
		}
	}

	func testDeletion_10000_OC_iterations() {
		measureOCDeletionPerformance(times: 10000)
	}

	func testDeletion_2000_OC_iterations() {
		measureOCDeletionPerformance(times: 2000)
	}

	func testDeletion_1000_OC_iterations() {
		measureOCDeletionPerformance(times: 1000)
	}

	func testDeletion_100_OC_iterations() {
		measureOCDeletionPerformance(times: 100)
	}

	func testDeletion_10_OC_iterations() {
		measureOCDeletionPerformance(times: 10)
	}

	func measureOCReadPerformance(times: Int) {
		for i in 0 ..< times {
			let children = Children(context: mainContext)
			children.value = Int64(i)
		}

		mainContext.processPendingChanges()

		let collection = Children.query(self.mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)
		expect { try collection.fetch() }.toNot(throwError())

		measure {
			// verify results
			expect(collection.sectionCount) == 1
			expect(collection.rowCount(for: 0)) == times

			for indexPath in collection.indices {
				expect(collection[indexPath].value) == Int64(indexPath.row)
			}
		}

		self.mainContext.reset()
	}

	func testRead_10000_OC_iterations() {
		measureOCReadPerformance(times: 10000)
	}

	func testRead_2000_OC_iterations() {
		measureOCReadPerformance(times: 2000)
	}

	func testRead_1000_OC_iterations() {
		measureOCReadPerformance(times: 1000)
	}

	func testRead_100_OC_iterations() {
		measureOCReadPerformance(times: 100)
	}

	func testRead_10_OC_iterations() {
		measureOCReadPerformance(times: 10)
	}

	func measureOCInsertionPerformance(times: Int) {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		measure {
			self.mainContext.reset()
			expect { try collection.fetch() }.toNot(throwError())

			for i in 0 ..< times {
				let children = Children(context: self.mainContext)
				children.value = Int64(i)
			}

			self.mainContext.processPendingChanges()

			// verify results
			expect(collection.sectionCount) == 1
			expect(collection.rowCount(for: 0)) == times
		}

		self.mainContext.reset()
	}

	func testInsertion_10000_OC_iterations() {
		measureOCInsertionPerformance(times: 10000)
	}

	func testInsertion_2000_OC_iterations() {
		measureOCInsertionPerformance(times: 2000)
	}

	func testInsertion_1000_OC_iterations() {
		measureOCInsertionPerformance(times: 1000)
	}

	func testInsertion_100_OC_iterations() {
		measureOCInsertionPerformance(times: 100)
	}

	func testInsertion_10_OC_iterations() {
		measureOCInsertionPerformance(times: 10)
	}

	func measureFRCDeletionPerformance(times: Int) {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver

		measure {
			var children = [Children]()
			children.reserveCapacity(times)

			for i in 0 ..< times {
				let child = Children(context: self.mainContext)
				child.value = Int64(i)
				children.append(child)
			}
			self.mainContext.processPendingChanges()

			expect { try controller.performFetch() }.toNot(throwError())

			expect(controller.fetchedObjects!.count) == times

			children.forEach(self.mainContext.delete)
			self.mainContext.processPendingChanges()

			expect(controller.fetchedObjects!.count) == 0
			self.mainContext.reset()
		}
	}

	func testDeletion_10000_FRC_iteration() {
		measureFRCDeletionPerformance(times: 10000)
	}

	func testDeletion_2000_FRC_iteration() {
		measureFRCDeletionPerformance(times: 2000)
	}

	func testDeletion_1000_FRC_iterations() {
		measureFRCDeletionPerformance(times: 1000)
	}

	func testDeletion_100_FRC_iterations() {
		measureFRCDeletionPerformance(times: 100)
	}

	func testDeletion_10_FRC_iterations() {
		measureFRCDeletionPerformance(times: 10)
	}

	func measureFRCInsertionPerformance(times: Int) {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver

		measure {
			self.mainContext.reset()
			expect { try controller.performFetch() }.toNot(throwError())

			for i in 0 ..< times {
				let children = Children(context: self.mainContext)
				children.value = Int64(i)
			}

			self.mainContext.processPendingChanges()

			// verify results
			expect(controller.sections?.count) == 1
			expect(controller.sections!.first!.numberOfObjects) == times
		}

		self.mainContext.reset()
	}

	func testInsertion_10000_FRC_iteration() {
		measureFRCInsertionPerformance(times: 10000)
	}

	func testInsertion_2000_FRC_iteration() {
		measureFRCInsertionPerformance(times: 2000)
	}

	func testInsertion_1000_FRC_iterations() {
		measureFRCInsertionPerformance(times: 1000)
	}

	func testInsertion_100_FRC_iterations() {
		measureFRCInsertionPerformance(times: 100)
	}

	func testInsertion_10_FRC_iterations() {
		measureFRCInsertionPerformance(times: 10)
	}


	func measureFRCReadPerformance(times: Int) {
		for i in 0 ..< times {
			let children = Children(context: mainContext)
			children.value = Int64(i)
		}

		mainContext.processPendingChanges()

		let controller = Children.query(self.mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver

		expect { try controller.performFetch() }.toNot(throwError())

		measure {
			// verify results
			expect(controller.sections?.count) == 1
			expect(controller.sections!.first!.numberOfObjects) == times

			for objectIndex in 0 ..< controller.sections!.first!.numberOfObjects {
				XCTAssertTrue(controller.object(at: IndexPath(row: objectIndex, section: 0)).value == Int64(objectIndex))
			}
		}

		self.mainContext.reset()
	}

	func testRead_10000_FRC_iteration() {
		measureFRCReadPerformance(times: 10000)
	}

	func testRead_2000_FRC_iteration() {
		measureFRCReadPerformance(times: 2000)
	}

	func testRead_1000_FRC_iterations() {
		measureFRCReadPerformance(times: 1000)
	}

	func testRead_100_FRC_iterations() {
		measureFRCReadPerformance(times: 100)
	}

	func testRead_10_FRC_iterations() {
		measureFRCReadPerformance(times: 10)
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

class TestOperation: Operation {}
