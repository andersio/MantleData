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

	func testOCDeletionPerformance_10000_iterations() {
		measureOCDeletionPerformance(times: 10000)
	}

	func testOCDeletionPerformance_2000_iterations() {
		measureOCDeletionPerformance(times: 2000)
	}

	func testOCDeletionPerformance_1000_iterations() {
		measureOCDeletionPerformance(times: 1000)
	}

	func testOCDeletionPerformance_100_iterations() {
		measureOCDeletionPerformance(times: 100)
	}

	func testOCDeletionPerformance_10_iterations() {
		measureOCDeletionPerformance(times: 10)
	}

	func measureOCInsertionPerformance(times: Int) {
		let collection = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeCollection(prefetching: .none)

		expect { try collection.fetch() }.toNot(throwError())

		measure {
			for i in 0 ..< times {
				let children = Children(context: self.mainContext)
				children.value = Int64(i)
			}

			self.mainContext.processPendingChanges()

			// verify results
			for indexPath in collection.indices {
				expect(collection[indexPath].value) == Int64(indexPath.row)
			}

			self.mainContext.reset()
		}
	}

	func testOCInsertionPerformance_10000_iterations() {
		measureOCInsertionPerformance(times: 10000)
	}

	func testOCInsertionPerformance_2000_iterations() {
		measureOCInsertionPerformance(times: 2000)
	}

	func testOCInsertionPerformance_1000_iterations() {
		measureOCInsertionPerformance(times: 1000)
	}

	func testOCInsertionPerformance_100_iterations() {
		measureOCInsertionPerformance(times: 100)
	}

	func testOCInsertionPerformance_10_iterations() {
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

	func testFRCDeletionPerformance_2000_iteration() {
		measureFRCDeletionPerformance(times: 2000)
	}

	func testFRCDeletionPerformance_1000_iterations() {
		measureFRCDeletionPerformance(times: 1000)
	}

	func testFRCDeletionPerformance_100_iterations() {
		measureFRCDeletionPerformance(times: 100)
	}

	func testFRCDeletionPerformance_10_iterations() {
		measureFRCDeletionPerformance(times: 10)
	}

	func measureFRCInsertionPerformance(times: Int) {
		let controller = Children.query(mainContext)
			.sort(by: .ascending("value"))
			.makeController()

		let receiver = Receiver()
		controller.delegate = receiver
		expect { try controller.performFetch() }.toNot(throwError())

		measure {
			for i in 0 ..< times {
				let children = Children(context: self.mainContext)
				children.value = Int64(i)
			}

			self.mainContext.processPendingChanges()

			// verify results
			var i = 0
			for (sectionIndex, section) in (controller.sections ?? []).enumerated() {
				for objectIndex in 0 ..< section.numberOfObjects {
					expect(controller.object(at: IndexPath(row: objectIndex, section: sectionIndex)).value) == Int64(i)
					i += 1
				}
			}

			self.mainContext.reset()
		}
	}

	func testFRCInsertionPerformance_2000_iteration() {
		measureFRCInsertionPerformance(times: 2000)
	}

	func testFRCInsertionPerformance_1000_iterations() {
		measureFRCInsertionPerformance(times: 1000)
	}

	func testFRCInsertionPerformance_100_iterations() {
		measureFRCInsertionPerformance(times: 100)
	}

	func testFRCInsertionPerformance_10_iterations() {
		measureFRCInsertionPerformance(times: 10)
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
