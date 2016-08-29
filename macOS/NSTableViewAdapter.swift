//
//  DynamicTableAdapter.swift
//  Galleon
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Cocoa
import ReactiveCocoa

private let sectionHeaderViewIdentifier = "_TableViewSectionHeader"

public struct TableViewAdapterConfiguration<V: ViewModel> {
	public typealias CellConfigurationBlock = (_ cell: NSView, _ viewModel: V) -> Void
	public typealias SectionHeaderConfigurationBlock = (_ cell: NSView, _ title: String?) -> Void

	public var allowSectionHeaderSelection = false

	public var shouldReloadRowsForUpdatedObjects = false
	public var rowAnimation: NSTableViewAnimationOptions = .slideUp

	fileprivate var columnCellConfigurators: [String: (viewIdentifier: String, block: CellConfigurationBlock, nib: NSNib?)] = [:]
	fileprivate var sectionHeaderConfigurator: (block: SectionHeaderConfigurationBlock, nib: NSNib)?

	fileprivate var sectionHeightBlock: ((Int) -> CGFloat)?
	fileprivate var rowHeightBlock: ((IndexPath) -> CGFloat)?

	public init() { }

	public mutating func registerSectionHeader(nib: NSNib, configurator: SectionHeaderConfigurationBlock) {
		sectionHeaderConfigurator = (block: configurator, nib: nib)
	}

	public mutating func registerColumn(columnIdentifier: String, nib: NSNib? = nil, configurator: CellConfigurationBlock) {
		columnCellConfigurators[columnIdentifier] = (columnIdentifier, configurator, nib)
	}

	public mutating func registerSectionHeightBlock(block: ((Int) -> CGFloat)? = nil) {
		sectionHeightBlock = block
	}

	public mutating func registerRowHeightBlock(block: ((IndexPath) -> CGFloat)? = nil) {
		rowHeightBlock = block
	}
}

final public class TableViewAdapter<V: ViewModel>: NSObject, NSTableViewDataSource, NSTableViewDelegate {
	public let set: ViewModelMappingSet<V>
	private let configuration: TableViewAdapterConfiguration<V>
	private var flattenedRanges: [Range<Int>] = []

	public init(set: ViewModelMappingSet<V>, configuration: TableViewAdapterConfiguration<V>) {
		self.set = set
		self.configuration = configuration

		super.init()
		computeFlattenedRanges()
	}

	@discardableResult
	private func computeFlattenedRanges() -> [Range<Int>] {
		let old = flattenedRanges

		flattenedRanges.removeAll(keepingCapacity: true)
		for sectionIndex in 0 ..< set.sectionCount {
			let startIndex = flattenedRanges.last?.upperBound ?? 0
			let range = Range(startIndex ... startIndex + set.rowCount(for: sectionIndex))
			flattenedRanges.append(range)
		}

		return old
	}

	private func indexPath(fromFlattened index: Int) -> IndexPath {
		for (sectionIndex, range) in flattenedRanges.enumerated() {
			if range.lowerBound == index {
				return IndexPath(section: sectionIndex)
			} else if range.contains(index) {
				return IndexPath(row: index - range.lowerBound - 1,
				                 section: sectionIndex)
			}
		}

		preconditionFailure("Index is out of range.")
	}

	private func flattenedIndex(fromSectioned index: IndexPath) -> Int {
		return flattenedRanges[index.section].lowerBound + index.row + 1
	}

	public func bind(tableView: NSTableView) {
		tableView.dataSource = self
		tableView.delegate = self

		if let headerConfig = configuration.sectionHeaderConfigurator {
			tableView.register(headerConfig.nib, forIdentifier: sectionHeaderViewIdentifier)
		}

		for (identifier, cellConfig) in configuration.columnCellConfigurators {
			if let nib = cellConfig.nib {
				tableView.register(nib, forIdentifier: identifier)
			}
		}

		set.eventsProducer
			.take(during: self.rac_lifetime)
			.startWithNext { [unowned self, weak tableView] in
				switch($0) {
				case .reloaded:
					self.computeFlattenedRanges()
					tableView?.reloadData()

				case let .updated(changes):
					let previousRanges = self.computeFlattenedRanges()

					tableView?.beginUpdates()

					if let indexSet = changes.deletedSections {
						let flattenedSet = IndexSet(indexSet.map { previousRanges[$0].lowerBound })
						tableView?.removeRows(at: flattenedSet, withAnimation: self.configuration.rowAnimation)
					}

					if let indexPaths = changes.deletedRows {
						let flattenedSet = IndexSet(indexPaths.map(self.flattenedIndex(fromSectioned:)))
						tableView?.removeRows(at: flattenedSet, withAnimation: self.configuration.rowAnimation)
					}

					if let indexSet = changes.insertedSections {
						let flattenedSet = IndexSet(indexSet.map { previousRanges[$0].lowerBound })
						tableView?.insertRows(at: flattenedSet, withAnimation: self.configuration.rowAnimation)
					}

					if let indexPathPairs = changes.movedRows {
						for (old, new) in indexPathPairs {
							tableView?.moveRow(at: self.flattenedIndex(fromSectioned: old),
							                   to: self.flattenedIndex(fromSectioned: new))
						}
					}

					if let indexPaths = changes.insertedRows {
						let flattenedSet = IndexSet(indexPaths.map(self.flattenedIndex(fromSectioned:)))
						tableView?.insertRows(at: flattenedSet, withAnimation: self.configuration.rowAnimation)
					}

					tableView?.endUpdates()
				}
		}
		try! set.fetch()
	}

	public func isGroupRow(at index: Int) -> Bool {
		return indexPath(fromFlattened: index).count == 1
	}

	// DELEGATE: NSTableViewDataSource

	public func numberOfRows(in tableView: NSTableView) -> Int {
		return set.sectionCount + (0 ..< set.sectionCount).reduce(0) { $0 + set.rowCount(for: $1) }
	}

	// DELEGATE: NSTableViewDelegate

	public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		let indexPath = self.indexPath(fromFlattened: row)
		if indexPath.count == 1 {
			return configuration.sectionHeightBlock?(indexPath.section) ?? tableView.rowHeight
		} else {
			return configuration.rowHeightBlock?(indexPath) ?? tableView.rowHeight
		}
	}

	public func tableView(_ tableView: NSTableView, isGroupRow index: Int) -> Bool {
		return isGroupRow(at: index)
	}

	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let indexPath = self.indexPath(fromFlattened: row)

		if indexPath.count == 1, let headerConfig = configuration.sectionHeaderConfigurator {
			guard let view = tableView.make(withIdentifier: sectionHeaderViewIdentifier, owner: tableView) else {
				preconditionFailure("The view identifier must be pre-registered via `NSTableView.registerNib`.")
			}

			headerConfig.block(view, set.sectionName(for: indexPath.section))
			return view
		}

		if let columnIdentifier = tableColumn?.identifier,
		   let columnConfig = configuration.columnCellConfigurators[columnIdentifier] {
			guard let view = tableView.make(withIdentifier: columnConfig.viewIdentifier, owner: tableView) else {
				preconditionFailure("The view identifier must be pre-registered via `NSTableView.registerNib`.")
			}

			columnConfig.block(view, set[indexPath])
			return view
		}

		return nil
	}

	public func tableView(_ tableView: NSTableView, shouldSelectRow index: Int) -> Bool {
		return !configuration.allowSectionHeaderSelection && isGroupRow(at: index)
	}
}
