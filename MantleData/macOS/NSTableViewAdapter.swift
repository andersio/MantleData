//
//  DynamicTableAdapter.swift
//  Galleon
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Cocoa
import ReactiveSwift
import ReactiveCocoa

public struct NSTableViewAdapterConfig {
	public var hidesSectionHeader = false
	public var rowAnimation: NSTableViewAnimationOptions = .slideUp

	public init() {}
}

public protocol NSTableViewAdapterProvider: class {
}

final public class NSTableViewAdapter<ViewModel, Provider: NSTableViewAdapterProvider>: NSObject, NSTableViewDataSource {
	private let set: ViewModelCollection<ViewModel>
	private unowned let provider: Provider
	private let config: NSTableViewAdapterConfig
	private var flattenedRanges: [Range<Int>] = []

	private var offset: Int {
		return config.hidesSectionHeader ? 0 : 1
	}

	public let disposable: Disposable

	private init(set: ViewModelCollection<ViewModel>, provider: Provider, config: NSTableViewAdapterConfig, disposable: Disposable) {
		self.set = set
		self.provider = provider
		self.config = config
		self.disposable = disposable

		super.init()
		computeFlattenedRanges()
	}

	@discardableResult
	private func computeFlattenedRanges() -> [Range<Int>] {
		let old = flattenedRanges

		flattenedRanges.removeAll(keepingCapacity: true)
		for sectionIndex in 0 ..< set.sectionCount {
			let startIndex = flattenedRanges.last?.upperBound ?? 0
			let range = Range(startIndex ... startIndex + set.rowCount(for: sectionIndex) + (config.hidesSectionHeader ? -1 : 0))
			flattenedRanges.append(range)
		}

		return old
	}

	public func indexPath(fromFlattened index: Int) -> IndexPath {
		for (sectionIndex, range) in flattenedRanges.enumerated() {
			if !config.hidesSectionHeader && range.lowerBound == index {
				return IndexPath(section: sectionIndex)
			} else if range.contains(index) {
				return IndexPath(row: index - range.lowerBound - offset,
				                 section: sectionIndex)
			}
		}

		preconditionFailure("Index is out of range.")
	}

	public func flattenedIndex(fromSectioned index: IndexPath) -> Int {
		return flattenedIndex(fromSectioned: index, for: flattenedRanges)
	}

	private func flattenedIndex(fromSectioned index: IndexPath, for ranges: [Range<Int>]) -> Int {
		return ranges[index.section].lowerBound + index.row + offset
	}

	public func hasGroupRow(at index: Int) -> Bool {
		return !config.hidesSectionHeader && flattenedRanges.contains { $0.lowerBound == index }
	}

	public func numberOfRows(in tableView: NSTableView) -> Int {
		return (config.hidesSectionHeader ? 0 : set.sectionCount)
			+ (0 ..< set.sectionCount).reduce(0) { $0 + set.rowCount(for: $1) }
	}

	public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		return nil
	}

	@discardableResult
	public static func bind(
		_ tableView: NSTableView,
		with set: ViewModelCollection<ViewModel>,
		provider: Provider,
		config: NSTableViewAdapterConfig
	) -> NSTableViewAdapter<ViewModel, Provider> {
		let disposable = CompositeDisposable()
		let adapter = NSTableViewAdapter(set: set, provider: provider, config: config, disposable: disposable)
		tableView.dataSource = adapter

		disposable += set.events
			.take(during: tableView.reactive.lifetime)
			.observeValues { [adapter, weak tableView] event in
				guard let tableView = tableView else { return }
				switch event {
				case .reloaded:
					adapter.computeFlattenedRanges()
					tableView.reloadData()

				case let .updated(changes):
					let previousRanges = adapter.computeFlattenedRanges()

					tableView.beginUpdates()

					let removed = IndexSet(changes.deletedSections.flatMap { CountableRange(previousRanges[$0]) })
					tableView.removeRows(at: removed, withAnimation: config.rowAnimation)

					let removed2 = IndexSet(changes.deletedRows.map { adapter.flattenedIndex(fromSectioned: $0, for: previousRanges) })
					tableView.removeRows(at: removed2, withAnimation: config.rowAnimation)

					let inserted = IndexSet(changes.insertedSections.flatMap { CountableRange(adapter.flattenedRanges[$0]) })
					tableView.insertRows(at: inserted, withAnimation: config.rowAnimation)

					let inserted2 = IndexSet(changes.insertedRows.map(adapter.flattenedIndex(fromSectioned:)))
					tableView.insertRows(at: inserted2, withAnimation: config.rowAnimation)

					for (old, new) in changes.movedRows {
						tableView.moveRow(at: adapter.flattenedIndex(fromSectioned: old),
						                  to: adapter.flattenedIndex(fromSectioned: new))
					}

					tableView.endUpdates()
				}
			}

		return adapter
	}
}
