//
//  TableViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import UIKit
import ReactiveCocoa

public protocol UITableViewAdapterProvider: class {
	func cellForRow(at indexPath: IndexPath) -> UITableViewCell
}

public struct UITableViewAdapterConfig {
	public var insertingAnimation: UITableViewRowAnimation = .automatic
	public var deletingAnimation: UITableViewRowAnimation = .automatic
	public var updatingAnimation: UITableViewRowAnimation = .automatic
}

final public class UITableViewAdapter<V: ViewModel, Provider: UITableViewAdapterProvider>: NSObject, UITableViewDataSource {
	private let set: ViewModelMappingSet<V>
	private let provider: Provider

	fileprivate init(set: ViewModelMappingSet<V>, provider: Provider) {
		self.set = set
		self.provider = provider
		super.init()
	}

	public func numberOfSections(in tableView: UITableView) -> Int {
		return set.sectionCount
	}

	public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return set.sectionName(for: section)
	}

	public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		return provider.cellForRow(at: indexPath)
	}

	public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return set.rowCount(for: section)
	}

	@discardableResult
	public static func bind(
		_ tableView: UITableView,
		with set: ViewModelMappingSet<V>,
		provider: Provider,
		config: UITableViewAdapterConfig
	) -> UITableViewAdapter<V, Provider> {
		let adapter = UITableViewAdapter(set: set, provider: provider)
		tableView.dataSource = adapter

		defer { try! set.fetch() }

		set.eventsProducer
			.take(until: tableView.willDeinitProducer)
			.startWithNext { [unowned tableView] event in
				switch event {
				case .reloaded:
					tableView.reloadData()

				case let .updated(changes):
					tableView.beginUpdates()

					if let indices = changes.deletedSections {
						tableView.deleteSections(indices, with: config.deletingAnimation)
					}

					if let indexPaths = changes.deletedRows {
						tableView.deleteRows(at: indexPaths, with: config.deletingAnimation)
					}

					if let indices = changes.insertedSections {
						tableView.insertSections(indices, with: config.insertingAnimation)
					}

					if let indexPathPairs = changes.movedRows {
						for (source, destination) in indexPathPairs {
							tableView.moveRow(at: source, to: destination)
						}
					}

					if let indexPaths = changes.insertedRows {
						tableView.insertRows(at: indexPaths, with: config.insertingAnimation)
					}

					tableView.endUpdates()
				}
			}

		return adapter
	}
}
