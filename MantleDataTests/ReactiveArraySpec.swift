import Nimble
import Quick
import MantleData
import ReactiveSwift
import enum Result.NoError

class ReactiveArraySpec: QuickSpec {
	override func spec() {
		describe("ReactiveArray") {
			var array: ReactiveArray<Int>!
			var changes: [SectionedCollectionChanges]!

			beforeEach {
				array = ReactiveArray()
				changes = []

				array.events.observeValues { event in
					switch event {
					case .reloaded:
						break

					case let .updated(change):
						changes.append(change)
					}
				}

				expect(changes.isEmpty) == true
			}

			afterEach {
				array = nil
			}

			context("insertions") {
				it("should emit changes for individual insertions") {
					array.insert(1, at: 0)
					array.insert(2, at: 0)
					array.insert(3, at: 0)

					expect(Array(array!)) == [3, 2, 1]

					expect(changes.count) == 3

					let insertedRows = changes.flatMap { $0.insertedRows }
					expect(insertedRows.count) == 3
					expect(insertedRows) == Array(repeating: IndexPath(row: 0, section: 0), count: 3)
				}

				it("should emit changes for batch insertions at the same position") {
					array.batchUpdate {
						array.insert(1, at: 0)
						array.insert(2, at: 0)
						array.insert(3, at: 0)
					}

					expect(Array(array!)) == [3, 2, 1]

					expect(changes.count) == 1

					let insertedRows = changes.flatMap { $0.insertedRows }
					expect(insertedRows.count) == 3
					expect(insertedRows).to(contain((0 ... 2).map { IndexPath(row: $0, section: 0) }))
				}

				it("should emit changes for batch insertions at mixed positions") {
					array.batchUpdate {
						array.insert(1, at: 0)
						array.insert(2, at: 1)
						array.insert(3, at: 0)
						array.insert(4, at: 1)
					}

					expect(Array(array!)) == [3, 4, 1, 2]

					expect(changes.count) == 1

					let insertedRows = changes.flatMap { $0.insertedRows }
					expect(insertedRows.count) == 4
					expect(insertedRows).to(contain((0 ... 3).map { IndexPath(row: $0, section: 0) }))
				}

				it("should emit changes for batch insertions at mixed positions") {
					array.append(-2)
					array.append(-1)

					array.batchUpdate {
						array.insert(0, at: 0)
						array.append(1)
						array.insert(2, at: 0)
						array.append(3)
					}

					expect(Array(array!)) == [2, 0, -2, -1, 1, 3]
					expect(changes.count) == 3

					let insertedRows = changes.flatMap { $0.insertedRows }
					expect(insertedRows.count) == 6
					expect(insertedRows).to(contain([IndexPath(row: 0, section: 0),
					                                 IndexPath(row: 1, section: 0),
					                                 IndexPath(row: 0, section: 0),
					                                 IndexPath(row: 1, section: 0),
					                                 IndexPath(row: 4, section: 0),
					                                 IndexPath(row: 5, section: 0)]))
				}
			}

			context("deletions") {
				beforeEach {
					array.batchUpdate {
						array.insert(0, at: 0)
						array.insert(1, at: 1)
						array.insert(2, at: 2)
						array.insert(3, at: 3)
					}

					expect(changes.count) == 1
					changes = []
				}

				it("should emit changes for individual deletions") {
					let first = array.remove(at: 0)
					let second = array.remove(at: 1)

					expect(Array(array!)) == [1, 3]
					expect(first) == 0
					expect(second) == 2

					expect(changes.count) == 2

					let deletedRows = changes.flatMap { $0.deletedRows }
					expect(deletedRows.count) == 2
					expect(deletedRows).to(contain([IndexPath(row: 0, section: 0),
					                                IndexPath(row: 1, section: 0)]))
				}

				it("should emit changes for batch deletions at the same position") {
					var first: Int!
					var second: Int!

					array.batchUpdate {
						first = array.remove(at: 0)
						second = array.remove(at: 1)
					}

					expect(Array(array!)) == [2, 3]
					expect(first) == 0
					expect(second) == 1

					expect(changes.count) == 1

					let deletedRows = changes.flatMap { $0.deletedRows }
					expect(deletedRows.count) == 2
					expect(deletedRows).to(contain([IndexPath(row: 0, section: 0),
					                                IndexPath(row: 1, section: 0)]))
				}

				it("should emit changes for batch deletions at mixed positions") {
					var results = [Int]()

					array.batchUpdate {
						results.append(array.remove(at: 3))
						results.append(array.remove(at: 1))
						results.append(array.remove(at: 2))
					}

					expect(Array(array!)) == [0]
					expect(results) == [3, 1, 2]

					expect(changes.count) == 1

					let deletedRows = changes.flatMap { $0.deletedRows }
					expect(deletedRows.count) == 3
					expect(deletedRows).to(contain([IndexPath(row: 1, section: 0),
					                                IndexPath(row: 2, section: 0),
					                                IndexPath(row: 3, section: 0)]))
				}
			}

			context("updates") {
				beforeEach {
					array.batchUpdate {
						array.insert(0, at: 0)
						array.insert(1, at: 1)
						array.insert(2, at: 2)
						array.insert(3, at: 3)
					}

					expect(changes.count) == 1
					changes = []
				}

				it("should emit changes for individual updates") {
					array[1] = 10
					array[1] = 20
					array[1] = 30
					array[1] = 40

					expect(Array(array!)) == [0, 40, 2, 3]

					expect(changes.count) == 4

					let updatedRows = changes.flatMap { $0.updatedRows }
					expect(updatedRows.count) == 4
					expect(updatedRows) == Array(repeating: IndexPath(row: 1, section: 0), count: 4)
				}

				it("should emit changes for batch updates at the same position") {
					array.batchUpdate {
						array[1] = 10
						array[1] = 20
						array[1] = 30
						array[1] = 40
					}

					expect(Array(array!)) == [0, 40, 2, 3]

					expect(changes.count) == 1

					let updatedRows = changes.flatMap { $0.updatedRows }
					expect(updatedRows.count) == 1
					expect(updatedRows) == Array(repeating: IndexPath(row: 1, section: 0), count: 1)
				}

				it("should emit changes for batch updates at mixed positions") {
					array.batchUpdate {
						array[3] = 10
						array[1] = 20
						array[2] = 30
						array[0] = 40
					}

					expect(Array(array!)) == [40, 20, 30, 10]

					expect(changes.count) == 1

					let updatedRows = changes.flatMap { $0.updatedRows }
					expect(updatedRows.count) == 4
					expect(updatedRows).to(contain((0 ... 3).map { IndexPath(row: $0, section: 0) }))
				}
			}

			context("mixed") {
				it("should emit changes for batch, mixed mutations") {
					array.append(-2)
					array.append(-1)

					array.batchUpdate {
						array.insert(0, at: 0)
						array.append(1)
						array.insert(2, at: 0)
						array.append(3)
					}

					expect(Array(array!)) == [2, 0, -2, -1, 1, 3]
					expect(changes.count) == 3

					let insertedRows = changes.flatMap { $0.insertedRows }
					expect(insertedRows.count) == 6
					expect(insertedRows).to(contain([IndexPath(row: 0, section: 0),
					                                 IndexPath(row: 1, section: 0),
					                                 IndexPath(row: 0, section: 0),
					                                 IndexPath(row: 1, section: 0),
					                                 IndexPath(row: 4, section: 0),
					                                 IndexPath(row: 5, section: 0)]))

					changes = []

					array.batchUpdate {
						array[2] = -200
						array.remove(at: 0)
						array.remove(at: 4)
						array[5] = 30
					}

					expect(Array(array!)) == [0, -200, -1, 30]
					expect(changes.count) == 1

					let deletedRows = changes.flatMap { $0.deletedRows }
					let updatedRows = changes.flatMap { $0.updatedRows }
					expect(updatedRows.count) == 2
					expect(deletedRows.count) == 2
					expect(updatedRows).to(contain([IndexPath(row: 1, section: 0), IndexPath(row: 3, section: 0)]))
					expect(deletedRows).to(contain([IndexPath(row: 0, section: 0), IndexPath(row: 4, section: 0)]))
				}
			}
		}
	}
}
