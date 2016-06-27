//
//  TableViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import UIKit
import ReactiveCocoa

public enum AdapterSectionRegistration {
	case allSections
	case section(at: Int)
}

final public class TableViewAdapter<V: ViewModel>: NSObject, UITableViewDataSource {
	private let set: ViewModelMappingSet<V>

	private var cellConfigurators: [(reuseIdentifier: String, configurator: (cell: UITableViewCell, viewModel: V) -> Void)?]
	private var isUniform = false

	private var shouldReloadRowsForUpdatedObjects = false

	private var insertingAnimation: UITableViewRowAnimation = .automatic
	private var deletingAnimation: UITableViewRowAnimation = .automatic
	private var updatingAnimation: UITableViewRowAnimation = .automatic

	private var sectionNameMapper: ((position: Int, persistedName: String?) -> String?)?

	private var isEmpty: Bool = true
	public var emptiedObserver: (() -> Void)?
	public var unemptiedObserver: (() -> Void)?

	public init(set: ViewModelMappingSet<V>) {
		self.set = set
		self.cellConfigurators = []
	}

	private func ensureArraySize(for index: Int) {
		if cellConfigurators.endIndex <= index {
			cellConfigurators.append(contentsOf: Array(repeating: nil, count: index - cellConfigurators.startIndex))
		}
	}

	public func register<Cell: UITableViewCell>(for type: AdapterSectionRegistration,
	                     with reuseIdentifier: String,
											 class: Cell.Type,
											 applying cellConfigurator: (cell: Cell, viewModel: V) -> Void) -> Self {
		switch type {
		case let .section(index):
			assert(index >= 0, "section index must be greater than or equal to zero.")
			ensureArraySize(for: index)
			cellConfigurators[index] = (reuseIdentifier, { cellConfigurator(cell: $0 as! Cell, viewModel: $1) })

		case .allSections:
			isUniform = true
			cellConfigurators = []
			cellConfigurators.append((reuseIdentifier, { cellConfigurator(cell: $0 as! Cell, viewModel: $1) }))
		}

		return self
	}

	public func setAnimation(inserting insertingAnimation: UITableViewRowAnimation? = nil,
	                         deleting deletingAnimation: UITableViewRowAnimation? = nil,
													 updating updatingAnimation: UITableViewRowAnimation? = nil)
													 -> Self {
		self.insertingAnimation = insertingAnimation ?? self.insertingAnimation
		self.deletingAnimation = deletingAnimation ?? self.deletingAnimation
		self.updatingAnimation = updatingAnimation ?? self.updatingAnimation

		return self
	}

	public func mapSectionName(using transform: (position: Int, persistedName: String?) -> String?) -> Self {
		sectionNameMapper = transform
		return self
	}

	public func reloadUpdatedRows(enabling flag: Bool = true) -> Self {
		shouldReloadRowsForUpdatedObjects = flag
		return self
	}

	public func on(emptied: (() -> Void)?, unemptied: (() -> Void)?) -> Self {
		emptiedObserver = emptied ?? emptiedObserver
		unemptiedObserver = unemptied ?? unemptiedObserver
		return self
	}

	/// MARK: `UITableViewDataSource` conformance
	@discardableResult
	public func bind(_ tableView: UITableView) -> Disposable {
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
						let indexSet = IndexSet(converting: indices)
						tableView.deleteSections(indexSet, with: self.deletingAnimation)
					}

					if let indices = changes.reloadedSections {
						let indexSet = IndexSet(converting: indices)
						tableView.reloadSections(indexSet, with: self.updatingAnimation)
					}

					if let indexPaths = changes.deletedRows {
						tableView.deleteRows(at: indexPaths, with: self.deletingAnimation)
					}

					if self.shouldReloadRowsForUpdatedObjects, let indexPaths = changes.updatedRows {
						tableView.reloadRows(at: indexPaths, with: self.updatingAnimation)
					}

					if let indices = changes.insertedSections {
						let indexSet = IndexSet(converting: indices)
						tableView.insertSections(indexSet, with: self.insertingAnimation)
					}

					if let indexPathPairs = changes.movedRows {
						for (source, destination) in indexPathPairs {
							tableView.moveRow(at: source, to: destination)
						}
					}

					if let indexPaths = changes.insertedRows {
						tableView.insertRows(at: indexPaths, with: self.insertingAnimation)
					}

					tableView.endUpdates()
				}

				if !self.isEmpty && self.set.elementsCount == 0 {
					self.isEmpty = true
					self.emptiedObserver?()
				} else if self.isEmpty {
					self.isEmpty = false
					self.unemptiedObserver?()
				}
		}
	}

	public func numberOfSections(in tableView: UITableView) -> Int {
		return set.count
	}

	public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let sectionName = set[section].name.value
		return sectionNameMapper?(position: section, persistedName: sectionName) ?? sectionName
	}

	public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let (reuseIdentifier, configurator) = cellConfigurators[isUniform ? 0 : (indexPath as NSIndexPath).section]!
		let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier,
		                                                       for: indexPath)
		configurator(cell: cell, viewModel: set[indexPath])

		return cell
	}

	public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return set[section].count
	}
}
