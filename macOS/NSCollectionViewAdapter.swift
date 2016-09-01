//
//  DynamicTableAdapter.swift
//  Galleon
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Cocoa
import ReactiveCocoa

public struct NSCollectionViewAdapterConfig<V: ViewModel> {
	public var itemIdentifier: String
	public var headerIdentifier: String?
	public var footerIdentifier: String?
	public var gapIdentifier: String?

	public var itemConfigurator: (NSCollectionViewItem, V) -> Void
	public var headerConfigurator: ((NSView, Int, String?) -> Void)?
	public var footerConfigurator: ((NSView, Int, String?) -> Void)?
	public var gapConfigurator: ((NSView, Int) -> Void)?

	public init(itemIdentifier: String, itemConfigurator: @escaping (NSCollectionViewItem, V) -> Void) {
		self.itemIdentifier = itemIdentifier
		self.itemConfigurator = itemConfigurator
	}
}

final public class NSCollectionViewAdapter<V: ViewModel>: NSObject, NSCollectionViewDataSource {
	public static func bind(_ collectionView: NSCollectionView, with set: ViewModelMappingSet<V>, configuration: NSCollectionViewAdapterConfig<V>) {
		let adapter = NSCollectionViewAdapter(set: set, configuration: configuration)
		collectionView.dataSource = adapter

		collectionView.rac_lifetime.ended.observeCompleted { _ = adapter }

		set.eventsProducer
			.take(during: collectionView.rac_lifetime)
			.startWithNext { [unowned collectionView] in
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

					collectionView.performBatchUpdates(updater, completionHandler: nil)
				}
		}
		
		try! set.fetch()
	}

	public let set: ViewModelMappingSet<V>
	private let configuration: NSCollectionViewAdapterConfig<V>

	private init(set: ViewModelMappingSet<V>, configuration: NSCollectionViewAdapterConfig<V>) {
		self.set = set
		self.configuration = configuration
		super.init()
	}

	public func numberOfSections(in collectionView: NSCollectionView) -> Int {
		return set.sectionCount
	}

	public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return set.rowCount(for: section)
	}

	public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let item = collectionView.makeItem(withIdentifier: configuration.itemIdentifier,
		                                   for: indexPath)
		configuration.itemConfigurator(item, set[indexPath])
		return item
	}

	public func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> NSView {
		switch kind {
		case NSCollectionElementKindSectionHeader:
			let view = collectionView.makeSupplementaryView(ofKind: NSCollectionElementKindSectionHeader,
			                                            withIdentifier: configuration.headerIdentifier!,
			                                            for: indexPath)
			configuration.headerConfigurator?(view,
			                                  indexPath.section,
			                                  set.sectionName(for: indexPath.section))
			return view

		case NSCollectionElementKindSectionFooter:
			let view = collectionView.makeSupplementaryView(ofKind: NSCollectionElementKindSectionFooter,
			                                                withIdentifier: configuration.footerIdentifier!,
			                                                for: indexPath)
			configuration.footerConfigurator?(view,
			                                  indexPath.section,
			                                  set.sectionName(for: indexPath.section))
			return view

		case NSCollectionElementKindInterItemGapIndicator:
			let view = collectionView.makeSupplementaryView(ofKind: NSCollectionElementKindInterItemGapIndicator,
			                                                withIdentifier: configuration.gapIdentifier!,
			                                                for: indexPath)
			configuration.gapConfigurator?(view, indexPath.section)
			return view

		default:
			fatalError()
		}
	}
}
