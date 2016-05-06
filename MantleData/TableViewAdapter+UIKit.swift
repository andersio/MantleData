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

public struct TableViewAdapterConfiguration<V: ViewModel> {
	private var factories: [Int: (UITableView, V, NSIndexPath) -> UITableViewCell]
	public var isUniform = false
	public var shouldReloadRowsForUpdatedObjects = false
	public var rowAnimation: UITableViewRowAnimation = .Automatic
	public var sectionNameTransform: ((Int, String?) -> String?)?
	public var emptySetHandler: (Bool -> Void)?

	public init() {
		self.factories = [:]
	}

	public mutating func registerForAllSection(factory: (UITableView, V, NSIndexPath) -> UITableViewCell) {
		isUniform = true
		factories[-1] = factory
	}

	public mutating func registerSection(index: Int, factory: (UITableView, V, NSIndexPath) -> UITableViewCell) {
		precondition(index >= 0, "section index must be greater than or equal to zero.")
		factories[index] = factory
	}

	public func apply(indexPath: NSIndexPath, tableView: UITableView, viewModel: V) -> UITableViewCell {
		if isUniform {
			return factories[-1]!(tableView, viewModel, indexPath)
		}
		return factories[indexPath.section]!(tableView, viewModel, indexPath)
	}
}

final public class TableViewAdapter<V: ViewModel>: NSObject, UITableViewDataSource {
	private let set: ViewModelSet<V>
	private let configuration: TableViewAdapterConfiguration<V>
	private var isEmpty: Bool = true

	public init(set: ViewModelSet<V>, configuration: TableViewAdapterConfiguration<V>) {
		self.set = set
		self.configuration = configuration
	}

	public func bind(tableView: UITableView) {
		tableView.dataSource = self
		set.eventProducer
			.takeUntil(tableView.willDeinitProducer)
			.takeUntil(willDeinitProducer)
			.startWithNext { [unowned self, unowned tableView] in
				switch($0) {
				case .reloaded:
					tableView.reloadData()
					
				case .updated(let changes):
					tableView.beginUpdates()

					if let indexSet = changes.deletedSections {
						tableView.deleteSections(NSMutableIndexSet(converting: indexSet),
							withRowAnimation: self.configuration.rowAnimation)
					}

					if let indexSet = changes.reloadedSections {
						tableView.reloadSections(NSMutableIndexSet(converting: indexSet),
							withRowAnimation: self.configuration.rowAnimation)
					}

					if let indexPaths = changes.deletedRows {
						tableView.deleteRowsAtIndexPaths(indexPaths.map { NSIndexPath(converting: $0) },
							withRowAnimation: self.configuration.rowAnimation)
					}

					if self.configuration.shouldReloadRowsForUpdatedObjects, let indexPaths = changes.updatedRows {
						tableView.reloadRowsAtIndexPaths(indexPaths.map { NSIndexPath(converting: $0) },
							withRowAnimation: self.configuration.rowAnimation)
					}

					if let indexSet = changes.insertedSections {
						tableView.insertSections(NSMutableIndexSet(converting: indexSet),
							withRowAnimation: self.configuration.rowAnimation)
					}

					if let indexPathPairs = changes.movedRows {
						for (from, to) in indexPathPairs {
							tableView.moveRowAtIndexPath(NSIndexPath(converting: from),
								toIndexPath: NSIndexPath(converting: to))
						}
					}

					if let indexPaths = changes.insertedRows {
						tableView.insertRowsAtIndexPaths(indexPaths.map { NSIndexPath(converting: $0) },
							withRowAnimation: self.configuration.rowAnimation)
					}

					tableView.endUpdates()
				}

				if !self.isEmpty && self.set.numberOfObjects == 0 {
					self.isEmpty = true
					self.configuration.emptySetHandler?(true)
				} else if self.isEmpty {
					self.isEmpty = false
					self.configuration.emptySetHandler?(false)
				}
		}
		try! set.fetch()
	}

	public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return set.numberOfSections
	}

	public func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let sectionName = set.sectionName(for: section)
		return configuration.sectionNameTransform?(section, sectionName) ?? sectionName
	}

	public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		return configuration.apply(indexPath, tableView: tableView, viewModel: set[indexPath])
	}

	public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return set.numberOfRows(for: section)
	}
}