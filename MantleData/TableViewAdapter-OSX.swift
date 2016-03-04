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
	public typealias CellConfigurationBlock = (cell: NSView, viewModel: V) -> Void
	public typealias SectionHeaderConfigurationBlock = (cell: NSView, title: String?) -> Void

	public var allowSectionHeaderSelection = false

	public var shouldReloadRowsForUpdatedObjects = false
	public var rowAnimation: NSTableViewAnimationOptions = .SlideUp

	private var columnCellConfigurators: [String: (viewIdentifier: String, block: CellConfigurationBlock, nib: NSNib?)] = [:]
	private var sectionHeaderConfigurator: (block: SectionHeaderConfigurationBlock, nib: NSNib)?

	private var sectionHeightBlock: (Int -> CGFloat)?
	private var rowHeightBlock: (NSIndexPath -> CGFloat)?

	public init() { }

	public mutating func registerSectionHeader(nib: NSNib, configurator: SectionHeaderConfigurationBlock) {
		sectionHeaderConfigurator = (block: configurator, nib: nib)
	}

	public mutating func registerColumn(columnIdentifier: String, nib: NSNib? = nil, configurator: CellConfigurationBlock) {
		columnCellConfigurators[columnIdentifier] = (columnIdentifier, configurator, nib)
	}

	public mutating func registerSectionHeightBlock(block: (Int -> CGFloat)? = nil) {
		sectionHeightBlock = block
	}

	public mutating func registerRowHeightBlock(block: (NSIndexPath -> CGFloat)? = nil) {
		rowHeightBlock = block
	}
}

final public class TableViewAdapter<V: ViewModel>: NSObject, NSTableViewDataSource, NSTableViewDelegate {
	public let set: ViewModelSet<V>
	private let configuration: TableViewAdapterConfiguration<V>
	private var flattenedRanges: [Range<Int>] = []

	public init(set: ViewModelSet<V>, configuration: TableViewAdapterConfiguration<V>) {
		self.set = set
		self.configuration = configuration

		super.init()
		computeFlattenedRanges()
	}

	private func computeFlattenedRanges() -> [Range<Int>] {
		let cachedFlattenedRanges = flattenedRanges
		flattenedRanges.removeAll(keepCapacity: true)

		for sectionIndex in 0 ..< set.sectionCount {
			let startIndex = flattenedRanges.last?.endIndex ?? 0
			let range = startIndex ... startIndex + set.rowCountFor(sectionIndex)
			flattenedRanges.append(range)
		}

		return cachedFlattenedRanges
	}

	private func indexPathFrom(flattenedIndex: Int) -> NSIndexPath {
		for (sectionIndex, range) in flattenedRanges.enumerate() {
			if range.startIndex == flattenedIndex {
				return NSIndexPath(forSection: sectionIndex)
			} else if range.contains(flattenedIndex) {
				return NSIndexPath(forRow: flattenedIndex - range.startIndex - 1,
				                   inSection: sectionIndex)
			}
		}

		preconditionFailure("Index is out of range.")
	}

	private func flattenedIndexFrom(sectionedIndex: NSIndexPath) -> Int {
		return flattenedRanges[sectionedIndex.section].startIndex + sectionedIndex.row + 1
	}

	public func bind(tableView: NSTableView) {
		tableView.setDataSource(self)
		tableView.setDelegate(self)

		if let headerConfig = configuration.sectionHeaderConfigurator {
			tableView.registerNib(headerConfig.nib, forIdentifier: sectionHeaderViewIdentifier)
		}

		for (identifier, cellConfig) in configuration.columnCellConfigurators {
			if let nib = cellConfig.nib {
				tableView.registerNib(nib, forIdentifier: identifier)
			}
		}

		set.eventProducer
			.takeUntil(willDeinitProducer)
			.observeOn(UIScheduler())
			.startWithNext { [unowned self, weak tableView] in
				switch($0) {
				case .Reloaded:
					self.computeFlattenedRanges()
					tableView?.reloadData()

				case .Updated(let changes):
					let previousRanges = self.computeFlattenedRanges()

					tableView?.beginUpdates()

					if let indexSet = changes.indiceOfDeletedSections {
						let superset = NSMutableIndexSet()
						indexSet.map { previousRanges[$0].cocoaValue }.forEach(superset.addIndexesInRange)
						tableView?.removeRowsAtIndexes(superset, withAnimation: self.configuration.rowAnimation)
					}

					if let indexSet = changes.indiceOfReloadedSections {
						let superset = NSMutableIndexSet()
						indexSet.map { self.flattenedRanges[$0].cocoaValue }.forEach(superset.addIndexesInRange)
						tableView?.reloadDataForRowIndexes(superset,
							columnIndexes: NSIndexSet(indexesInRange: NSRange(location: 0, length: tableView!.numberOfColumns)))
					}

					if let indexPaths = changes.indexPathsOfDeletedRows {
						let superset = NSMutableIndexSet()
						indexPaths.map(self.flattenedIndexFrom).forEach(superset.addIndex)
						tableView?.removeRowsAtIndexes(superset, withAnimation: self.configuration.rowAnimation)
					}

					if self.configuration.shouldReloadRowsForUpdatedObjects, let indexPaths = changes.indexPathsOfUpdatedRows {
						let superset = NSMutableIndexSet()
						indexPaths.map(self.flattenedIndexFrom).forEach(superset.addIndex)
						tableView?.reloadDataForRowIndexes(superset,
							columnIndexes: NSIndexSet(indexesInRange: NSRange(location: 0, length: tableView!.numberOfColumns)))
					}

					if let indexSet = changes.indiceOfInsertedSections {
						let superset = NSMutableIndexSet()
						indexSet.map { self.flattenedRanges[$0].cocoaValue }.forEach(superset.addIndexesInRange)
						tableView?.insertRowsAtIndexes(superset, withAnimation: self.configuration.rowAnimation)
					}

					if let indexPathPairs = changes.indexPathsOfMovedRows {
						for (oldIndexPath, newIndexPath) in indexPathPairs {
							tableView?.moveRowAtIndex(self.flattenedIndexFrom(oldIndexPath),
								toIndex: self.flattenedIndexFrom(newIndexPath))
						}
					}

					if let indexPaths = changes.indexPathsOfInsertedRows {
						let superset = NSMutableIndexSet()
						indexPaths.map(self.flattenedIndexFrom).forEach(superset.addIndex)
						tableView?.insertRowsAtIndexes(superset, withAnimation: self.configuration.rowAnimation)
					}

					tableView?.endUpdates()
				}
		}
		try! set.fetch()
	}

	public func hasGroupRowAt(index: Int) -> Bool {
		return indexPathFrom(index).length == 1
	}

	// DELEGATE: NSTableViewDataSource

	public func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return set.sectionCount
			+ (0 ..< set.sectionCount).reduce(0, combine: { $0 + set.rowCountFor($1) })
	}

	// DELEGATE: NSTableViewDelegate

	public func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		let indexPath = indexPathFrom(row)
		if indexPath.length == 1 {
			return configuration.sectionHeightBlock?(indexPath.section) ?? tableView.rowHeight
		} else {
			return configuration.rowHeightBlock?(indexPath) ?? tableView.rowHeight
		}
	}

	public func tableView(tableView: NSTableView, isGroupRow row: Int) -> Bool {
		return hasGroupRowAt(row)
	}

	public func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let indexPath = indexPathFrom(row)

		if indexPath.length == 1, let headerConfig = configuration.sectionHeaderConfigurator {
			guard let view = tableView.makeViewWithIdentifier(sectionHeaderViewIdentifier, owner: tableView) else {
				preconditionFailure("The view identifier must be pre-registered via `NSTableView.registerNib`.")
			}

			headerConfig.block(cell: view, title: set.nameFor(indexPath.section))
			return view
		}

		if let columnIdentifier = tableColumn?.identifier, columnConfig = configuration.columnCellConfigurators[columnIdentifier] {
			guard let view = tableView.makeViewWithIdentifier(columnConfig.viewIdentifier, owner: tableView) else {
				preconditionFailure("The view identifier must be pre-registered via `NSTableView.registerNib`.")
			}

			columnConfig.block(cell: view, viewModel: set[indexPath])
			return view
		}

		return nil
	}

	public func tableView(tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if !configuration.allowSectionHeaderSelection && hasGroupRowAt(row) {
			return false
		}
		
		return true
	}
}