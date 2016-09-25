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

public enum NSCollectionViewSupplementaryViewKind: RawRepresentable {
	case header
	case footer
	case gap

	public var rawValue: String {
		switch self {
		case .header:
			return NSCollectionElementKindSectionHeader
		case .footer:
			return NSCollectionElementKindSectionFooter
		case .gap:
			return NSCollectionElementKindInterItemGapIndicator
		}
	}

	public init(rawValue: String) {
		switch rawValue {
		case NSCollectionElementKindSectionHeader:
			self = .header
		case NSCollectionElementKindSectionFooter:
			self = .footer
		case NSCollectionElementKindInterItemGapIndicator:
			self = .gap
		default:
			fatalError()
		}
	}
}

public struct NSCollectionViewAdapterConfig {
	// Workaround: Empty struct somehow crashes Swift runtime.
	public var placeholder = true
	public init() {}
}

public protocol NSCollectionViewAdapterProvider: class {
	func item(at indexPath: IndexPath) -> NSCollectionViewItem
	func supplementaryView(of kind: NSCollectionViewSupplementaryViewKind, at indexPath: IndexPath) -> NSView
}

final public class NSCollectionViewAdapter<V: ViewModel, Provider: NSCollectionViewAdapterProvider>: NSObject, NSCollectionViewDataSource {
	private let set: ViewModelMappingSet<V>
	private unowned let provider: Provider
	private let config: NSCollectionViewAdapterConfig

	public init(set: ViewModelMappingSet<V>, provider: Provider, config: NSCollectionViewAdapterConfig) {
		self.set = set
		self.provider = provider
		self.config = config

		super.init()
	}

	public func numberOfSections(in collectionView: NSCollectionView) -> Int {
		return set.sectionCount
	}

	public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return set.rowCount(for: section)
	}

	public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		return provider.item(at: indexPath)
	}

	public func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> NSView {
		return provider.supplementaryView(of: NSCollectionViewSupplementaryViewKind(rawValue: kind),
		                                  at: indexPath)
	}

	@discardableResult
	public static func bind(
		_ collectionView: NSCollectionView,
		with set: ViewModelMappingSet<V>,
		provider: Provider,
		config: NSCollectionViewAdapterConfig
	) -> NSCollectionViewAdapter<V, Provider> {
		let adapter = NSCollectionViewAdapter<V, Provider>(set: set, provider: provider, config: config)
		collectionView.dataSource = adapter

		collectionView.rac_lifetime.ended.observeCompleted { _ = adapter }

		set.eventsProducer
			.take(during: collectionView.rac_lifetime)
			.startWithValues { [unowned collectionView] in
				switch($0) {
				case .reloaded:
					collectionView.reloadData()

				case let .updated(changes):
					let updater = {
						if let indexSet = changes.deletedSections {
							collectionView.deleteSections(indexSet)
						}

						if let indexPaths = changes.deletedRows {
							collectionView.deleteItems(at: Set(indexPaths))
						}

						if let indexSet = changes.insertedSections {
							collectionView.insertSections(indexSet)
						}

						if let indexPathPairs = changes.movedRows {
							for (origin, destination) in indexPathPairs {
								collectionView.moveItem(at: origin, to: destination)
							}
						}

						if let indexPaths = changes.insertedRows {
							collectionView.insertItems(at: Set(indexPaths))
						}
					}

					collectionView.animator().performBatchUpdates(updater, completionHandler: nil)
				}
		}
		
		try! set.fetch()
		return adapter
	}
}
