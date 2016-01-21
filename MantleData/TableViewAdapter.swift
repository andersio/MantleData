//
//  DynamicTableAdapter.swift
//  Galleon
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import UIKit
import ReactiveCocoa

public struct TableViewAdapterConfiguration<V: ViewModel> {
	private var factories: [Int: (UITableView, V) -> UITableViewCell]
	public var isUniform: Bool = false

	public init() {
		self.factories = [:]
	}

	public mutating func registerForAllSection(factory: (UITableView, V) -> UITableViewCell) {
		isUniform = true
		factories[-1] = factory
	}

	public mutating func registerSection(index: Int, factory: (UITableView, V) -> UITableViewCell) {
		precondition(index >= 0, "section index must be greater than or equal to zero.")
		factories[index] = factory
	}

	public func apply(index: Int, tableView: UITableView, viewModel: V) -> UITableViewCell {
		if isUniform {
			return factories[-1]!(tableView, viewModel)
		}
		return factories[index]!(tableView, viewModel)
	}
}

final public class TableViewAdapter<V: ViewModel>: NSObject, UITableViewDataSource {
	private let set: ViewModelSet<V>
	private let configuration: TableViewAdapterConfiguration<V>

	public init(set: ViewModelSet<V>, configuration: TableViewAdapterConfiguration<V>) {
		self.set = set
		self.configuration = configuration
	}

	public func bind(tableView: UITableView) {
		tableView.dataSource = self
		set.eventProducer
			.takeUntil(willDeinitProducer)
			.observeOn(UIScheduler())
			.startWithNext { [weak tableView] in
				switch($0) {
				case .Reloaded:
					tableView?.reloadData()
					
				case .Updated(let changes):
					tableView?.beginUpdates()

					if let indexSet = changes.indiceOfDeletedSections {
						tableView?.deleteSections(indexSet, withRowAnimation: .Automatic)
					}

					if let indexPaths = changes.indexPathsOfDeletedRows {
						tableView?.deleteRowsAtIndexPaths(indexPaths, withRowAnimation: .Automatic)
					}

					if let indexSet = changes.indiceOfInsertedSections {
						tableView?.insertSections(indexSet, withRowAnimation: .Automatic)
					}

					if let indexPathPairs = changes.indexPathsOfMovedRows {
						for (from, to) in indexPathPairs {
							tableView?.moveRowAtIndexPath(from, toIndexPath: to)
						}
					}

					if let indexPaths = changes.indexPathsOfInsertedRows {
						tableView?.insertRowsAtIndexPaths(indexPaths, withRowAnimation: .Automatic)
					}

					tableView?.endUpdates()
				}
		}
		try! set.fetch()
	}

	public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return set.sectionCount
	}

	public func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return set.nameFor(section)
	}

	public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		return configuration.apply(indexPath.section, tableView: tableView, viewModel: set[indexPath])
	}

	public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return set.rowCountFor(section)
	}
}