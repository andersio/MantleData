//
//  TableViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import UIKit
import ReactiveCocoa

public enum TableViewAdapterRegistration {
	case allSections
	case section(at: Int)
}

final public class TableViewAdapter<V: ViewModel>: NSObject, UITableViewDataSource {
	private let set: ViewModelSet<V>
	private var isEmpty: Bool = true

	private var cellConfigurators: [(reuseIdentifier: String, configurator: (cell: UITableViewCell, viewModel: V) -> Void)?]
	public var isUniform = false
	public var shouldReloadRowsForUpdatedObjects = false
	public var rowAnimation: UITableViewRowAnimation = .Automatic
	public var sectionNameTransform: ((Int, String?) -> String?)?
	public var emptySetHandler: (Bool -> Void)?

	public init(set: ViewModelSet<V>) {
		self.set = set
		self.cellConfigurators = []
	}

	private func ensureArraySize(for index: Int) {
		if cellConfigurators.endIndex <= index {
			cellConfigurators.appendContentsOf(Array(count: index - cellConfigurators.startIndex, repeatedValue: nil))
		}
	}

	public func register(for type: TableViewAdapterRegistration,
	                     with reuseIdentifier: String,
											 applying cellConfigurator: (cell: UITableViewCell, viewModel: V) -> Void) -> TableViewAdapter {
		switch type {
		case let .section(index):
			assert(index >= 0, "section index must be greater than or equal to zero.")
			ensureArraySize(for: index)
			cellConfigurators[index] = (reuseIdentifier, cellConfigurator)

		case .allSections:
			isUniform = true
			cellConfigurators = [(reuseIdentifier, cellConfigurator)]
		}

		return self
	}

	public func bind(tableView: UITableView) -> Disposable {
		tableView.dataSource = self

		defer { try! set.fetch() }
		return set.eventProducer
			.takeUntil(tableView.willDeinitProducer)
			.startWithNext { [unowned tableView] in
				switch($0) {
				case .reloaded:
					tableView.reloadData()
					
				case .updated(let changes):
					tableView.beginUpdates()

					if let indexSet = changes.deletedSections {
						tableView.deleteSections(NSMutableIndexSet(converting: indexSet),
							withRowAnimation: self.rowAnimation)
					}

					if let indexSet = changes.reloadedSections {
						tableView.reloadSections(NSMutableIndexSet(converting: indexSet),
							withRowAnimation: self.rowAnimation)
					}

					if let indexPaths = changes.deletedRows {
						tableView.deleteRowsAtIndexPaths(indexPaths.map { NSIndexPath(converting: $0) },
							withRowAnimation: self.rowAnimation)
					}

					if self.shouldReloadRowsForUpdatedObjects, let indexPaths = changes.updatedRows {
						tableView.reloadRowsAtIndexPaths(indexPaths.map { NSIndexPath(converting: $0) },
							withRowAnimation: self.rowAnimation)
					}

					if let indexSet = changes.insertedSections {
						tableView.insertSections(NSMutableIndexSet(converting: indexSet),
							withRowAnimation: self.rowAnimation)
					}

					if let indexPathPairs = changes.movedRows {
						for (from, to) in indexPathPairs {
							tableView.moveRowAtIndexPath(NSIndexPath(converting: from),
								toIndexPath: NSIndexPath(converting: to))
						}
					}

					if let indexPaths = changes.insertedRows {
						tableView.insertRowsAtIndexPaths(indexPaths.map { NSIndexPath(converting: $0) },
							withRowAnimation: self.rowAnimation)
					}

					tableView.endUpdates()
				}

				if !self.isEmpty && self.set.numberOfObjects == 0 {
					self.isEmpty = true
					self.emptySetHandler?(true)
				} else if self.isEmpty {
					self.isEmpty = false
					self.emptySetHandler?(false)
				}
		}
	}

	public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return set.numberOfSections
	}

	public func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let sectionName = set.sectionName(for: section)
		return sectionNameTransform?(section, sectionName) ?? sectionName
	}

	public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let (reuseIdentifier, configurator) = cellConfigurators[isUniform ? 0 : indexPath.section]!
		let cell = tableView.dequeueReusableCellWithIdentifier(reuseIdentifier,
		                                                       forIndexPath: indexPath)
		configurator(cell: cell, viewModel: set[indexPath])

		return cell
	}

	public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return set.numberOfRows(for: section)
	}
}