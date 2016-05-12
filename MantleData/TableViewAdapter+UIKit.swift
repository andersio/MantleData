//
//  TableViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import UIKit
import ReactiveCocoa

public enum TableViewAdapterRegistration {
	case allSections
	case section(at: Int)
}

final public class TableViewAdapter<V: ViewModel>: NSObject, UITableViewDataSource {
	private let set: ViewModelSet<V>

	private var cellConfigurators: [(reuseIdentifier: String, configurator: (cell: UITableViewCell, viewModel: V) -> Void)?]
	private var isUniform = false

	private var shouldReloadRowsForUpdatedObjects = false

	private var insertingAnimation: UITableViewRowAnimation = .Automatic
	private var deletingAnimation: UITableViewRowAnimation = .Automatic
	private var updatingAnimation: UITableViewRowAnimation = .Automatic

	private var sectionNameMapper: ((position: Int, persistedName: String?) -> String?)?

	private var isEmpty: Bool = true
	public var emptiedObserver: (() -> Void)?
	public var unemptiedObserver: (() -> Void)?

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

	public func setAnimation(inserting insertingAnimation: UITableViewRowAnimation? = nil,
	                         deleting deletingAnimation: UITableViewRowAnimation? = nil,
													 updating updatingAnimation: UITableViewRowAnimation? = nil)
													 -> TableViewAdapter {
		self.insertingAnimation = insertingAnimation ?? self.insertingAnimation
		self.deletingAnimation = deletingAnimation ?? self.deletingAnimation
		self.updatingAnimation = updatingAnimation ?? self.updatingAnimation

		return self
	}

	public func mapSectionName(using transform: (position: Int, persistedName: String?) -> String?) -> TableViewAdapter {
		sectionNameMapper = transform
		return self
	}

	public func reloadUpdatedRows(enabling flag: Bool = true) -> TableViewAdapter {
		shouldReloadRowsForUpdatedObjects = flag
		return self
	}

	public func on(emptied emptied: (() -> Void)?, unemptied: (() -> Void)?) -> TableViewAdapter {
		emptiedObserver = emptied ?? emptiedObserver
		unemptiedObserver = unemptied ?? unemptiedObserver
		return self
	}

	public func bind(tableView: UITableView) -> Disposable {
		defer { try! set.fetch() }
		tableView.dataSource = self

		return set.eventProducer
			.takeUntil(tableView.willDeinitProducer)
			.startWithNext { [unowned tableView] event in
				switch event {
				case .reloaded:
					tableView.reloadData()
					
				case let .updated(changes):
					tableView.beginUpdates()

					if let indices = changes.deletedSections {
						let indexSet = NSMutableIndexSet(converting: indices)
						tableView.deleteSections(indexSet, withRowAnimation: self.deletingAnimation)
					}

					if let indices = changes.reloadedSections {
						let indexSet = NSMutableIndexSet(converting: indices)
						tableView.reloadSections(indexSet, withRowAnimation: self.updatingAnimation)
					}

					if let indexPaths = changes.deletedRows {
						tableView.deleteRowsAtIndexPaths(indexPaths as [NSIndexPath], withRowAnimation: self.deletingAnimation)
					}

					if self.shouldReloadRowsForUpdatedObjects, let indexPaths = changes.updatedRows {
						tableView.reloadRowsAtIndexPaths(indexPaths as [NSIndexPath], withRowAnimation: self.updatingAnimation)
					}

					if let indices = changes.insertedSections {
						let indexSet = NSMutableIndexSet(converting: indices)
						tableView.insertSections(indexSet, withRowAnimation: self.insertingAnimation)
					}

					if let indexPathPairs = changes.movedRows {
						for (from, to) in indexPathPairs {
							let source = NSIndexPath(converting: from)
							let destination = NSIndexPath(converting: to)
							tableView.moveRowAtIndexPath(source, toIndexPath: destination)
						}
					}

					if let indexPaths = changes.insertedRows {
						tableView.insertRowsAtIndexPaths(indexPaths as [NSIndexPath], withRowAnimation: self.insertingAnimation)
					}

					tableView.endUpdates()
				}

				if !self.isEmpty && self.set.objectCount == 0 {
					self.isEmpty = true
					self.emptiedObserver?()
				} else if self.isEmpty {
					self.isEmpty = false
					self.unemptiedObserver?()
				}
		}
	}

	/// MARK: `UITableViewDataSource` conformance

	public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return set.count
	}

	public func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let sectionName = set[section].name.value
		return sectionNameMapper?(position: section, persistedName: sectionName) ?? sectionName
	}

	public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let (reuseIdentifier, configurator) = cellConfigurators[isUniform ? 0 : indexPath.section]!
		let cell = tableView.dequeueReusableCellWithIdentifier(reuseIdentifier,
		                                                       forIndexPath: indexPath)
		configurator(cell: cell, viewModel: set[indexPath.section][indexPath.row])

		return cell
	}

	public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return set[section].count
	}
}