//
//  CollectionViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 14/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import UIKit
import ReactiveCocoa

public enum CollectionViewSupplementary {
	case header
	case footer
}

final public class CollectionViewAdapter<V: ViewModel>: NSObject, UICollectionViewDataSource {
	private let set: ViewModelMappingSet<V>

	private var cellConfigurators: [(reuseIdentifier: String, configurator: @escaping (_ cell: UICollectionViewCell, _ viewModel: V) -> Void)?]
	private var cellIsUniform = false

	private var headerCellConfigurators: [(reuseIdentifier: String, configurator: @escaping (_ view: UICollectionReusableView, _ sectionName: String?) -> Void)?]
	private var headerCellIsUniform = false

	private var footerCellConfigurators: [(reuseIdentifier: String, configurator: @escaping (_ view: UICollectionReusableView, _ sectionName: String?) -> Void)?]
	private var footerCellIsUniform = false

	private var shouldReloadRowsForUpdatedObjects = false

	private var isEmpty: Bool = true
	public var emptiedObserver: (@escaping () -> Void)?
	public var unemptiedObserver: (@escaping () -> Void)?

	public init(set: ViewModelMappingSet<V>) {
		self.set = set
		self.cellConfigurators = []
		self.headerCellConfigurators = []
		self.footerCellConfigurators = []
	}

	private func ensureArraySize(for index: Int) {
		if cellConfigurators.endIndex <= index {
			cellConfigurators.append(contentsOf: Array(repeating: nil, count: index - cellConfigurators.startIndex))
		}
	}

	private func ensureHeaderArraySize(for index: Int) {
		if headerCellConfigurators.endIndex <= index {
			headerCellConfigurators.append(contentsOf: Array(repeating: nil, count: index - headerCellConfigurators.startIndex))
		}
	}

	private func ensureFooterArraySize(for index: Int) {
		if footerCellConfigurators.endIndex <= index {
			footerCellConfigurators.append(contentsOf: Array(repeating: nil, count: index - footerCellConfigurators.startIndex))
		}
	}

	public func register<Cell: UICollectionViewCell>(for type: AdapterSectionRegistration,
	                         with reuseIdentifier: String,
	                              class: Cell.Type,
	                              applying cellConfigurator: @escaping (_ cell: Cell, _ viewModel: V) -> Void) -> Self {
		switch type {
		case let .section(index):
			assert(index >= 0, "section index must be greater than or equal to zero.")
			ensureArraySize(for: index)
			cellConfigurators[index] = (reuseIdentifier, { cellConfigurator($0 as! Cell, $1) })

		case .allSections:
			cellIsUniform = true
			cellConfigurators = []
			cellConfigurators.append((reuseIdentifier, { cellConfigurator($0 as! Cell, $1) }))
		}

		return self
	}

	public func registerHeader<View: UICollectionReusableView>(for type: AdapterSectionRegistration,
	                               with reuseIdentifier: String,
	                                    class: View.Type,
	                                    applying cellConfigurator: @escaping (_ view: View, _ sectionName: String?) -> Void) -> Self {
		switch type {
		case let .section(index):
			assert(index >= 0, "section index must be greater than or equal to zero.")
			ensureArraySize(for: index)
			headerCellConfigurators[index] = (reuseIdentifier, { cellConfigurator($0 as! View, $1) })

		case .allSections:
			headerCellIsUniform = true
			headerCellConfigurators = []
			headerCellConfigurators.append((reuseIdentifier, { cellConfigurator($0 as! View, $1) }))
		}
		
		return self
	}

	public func registerFooter<View: UICollectionReusableView>(for type: AdapterSectionRegistration,
	                               with reuseIdentifier: String,
	                                    class: View.Type,
																 applying cellConfigurator: @escaping (_ view: View, _ sectionName: String?) -> Void) -> Self {
		switch type {
		case let .section(index):
			assert(index >= 0, "section index must be greater than or equal to zero.")
			ensureArraySize(for: index)
			footerCellConfigurators[index] = (reuseIdentifier, { cellConfigurator($0 as! View, $1) })

		case .allSections:
			footerCellIsUniform = true
			footerCellConfigurators = []
			footerCellConfigurators.append((reuseIdentifier, { cellConfigurator($0 as! View, $1) }))
		}
		
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


	/// MARK: `UITableViewDataSource` conformance
	public func bind(_ collectionView: UICollectionView) -> Disposable {
		defer { try! set.fetch() }
		collectionView.dataSource = self

		return set.eventsProducer
			.take(until: collectionView.willDeinitProducer)
			.startWithNext { [unowned collectionView] event in
				switch event {
				case .reloaded:
					collectionView.reloadData()

				case let .updated(changes):
					collectionView.performBatchUpdates({

						if let indices = changes.deletedSections {
							collectionView.deleteSections(indices)
						}

						if let indexPaths = changes.deletedRows {
							collectionView.deleteItems(at: indexPaths)
						}

						if let indices = changes.insertedSections {
							collectionView.insertSections(indices)
						}

						if let indexPathPairs = changes.movedRows {
							for (source, destination) in indexPathPairs {
								collectionView.moveItem(at: source, to: destination)
							}
						}

						if let indexPaths = changes.insertedRows {
							collectionView.insertItems(at: indexPaths)
						}


						if !self.isEmpty && self.set.count == 0 {
							self.isEmpty = true
							self.emptiedObserver?()
						} else if self.isEmpty {
							self.isEmpty = false
							self.unemptiedObserver?()
						}
					}, completion: nil)
				}
		}
	}

	public func numberOfSections(in collectionView: UICollectionView) -> Int {
		return set.sectionCount
	}

	public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
		let sectionName = set.sectionName(for: indexPath.section)

		if kind == UICollectionElementKindSectionHeader {
			let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
			                                                                 withReuseIdentifier: headerCellConfigurators[(indexPath as NSIndexPath).section]!.reuseIdentifier,
			                                                                 for: indexPath)
			headerCellConfigurators[(indexPath as NSIndexPath).section]!.configurator(view, sectionName)
			return view
		} else {
			let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
			                                                                 withReuseIdentifier: footerCellConfigurators[(indexPath as NSIndexPath).section]!.reuseIdentifier,
			                                                                 for: indexPath)
			footerCellConfigurators[(indexPath as NSIndexPath).section]!.configurator(view, sectionName)
			return view
		}
	}

	public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let (reuseIdentifier, configurator) = cellConfigurators[cellIsUniform ? 0 : (indexPath as NSIndexPath).section]!
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier,
		                                                                 for: indexPath)
		configurator(cell, set[indexPath])

		return cell
	}

	public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return set.rowCount(for: section)
	}
}
