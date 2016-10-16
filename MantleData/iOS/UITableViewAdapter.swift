//
//  TableViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import UIKit
import ReactiveSwift
import ReactiveCocoa

public protocol UITableViewAdapterProvider: class {
	func cellForRow(at indexPath: IndexPath) -> UITableViewCell
}

public struct UITableViewAdapterConfig {
	public var insertingAnimation: UITableViewRowAnimation = .automatic
	public var deletingAnimation: UITableViewRowAnimation = .automatic
	public var updatingAnimation: UITableViewRowAnimation = .automatic

	public init() {}
}

final public class UITableViewAdapter<ViewModel, Provider: UITableViewAdapterProvider>: NSObject, UITableViewDataSource {
	private let set: ViewModelCollection<ViewModel>
	private let provider: Provider

	public let disposable: Disposable

	fileprivate init(set: ViewModelCollection<ViewModel>, provider: Provider, disposable: Disposable) {
		self.set = set
		self.provider = provider
		self.disposable = disposable

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
		with set: ViewModelCollection<ViewModel>,
		provider: Provider,
		config: UITableViewAdapterConfig
	) -> UITableViewAdapter<ViewModel, Provider> {
		let disposable = CompositeDisposable()

		let adapter = UITableViewAdapter(set: set,
		                                 provider: provider,
		                                 disposable: disposable)
		tableView.dataSource = adapter

		disposable += set.events
			.take(during: tableView.reactive.lifetime)
			.observeValues { [weak tableView] event in
				guard let tableView = tableView else {
					_ = adapter
					return
				}

				switch event {
				case .reloaded:
					tableView.reloadData()

				case let .updated(changes):
					tableView.beginUpdates()

					tableView.deleteSections(changes.deletedSections, with: config.deletingAnimation)
					tableView.deleteRows(at: changes.deletedRows, with: config.deletingAnimation)
					tableView.insertSections(changes.insertedSections, with: config.insertingAnimation)
					tableView.insertRows(at: changes.insertedRows, with: config.insertingAnimation)
					tableView.reloadRows(at: changes.updatedRows, with: config.updatingAnimation)

					for (source, destination) in changes.movedRows {
						tableView.moveRow(at: source, to: destination)
					}

					tableView.endUpdates()
				}
			}

		return adapter
	}
}
