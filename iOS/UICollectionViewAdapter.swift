//
//  CollectionViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 14/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import UIKit
import ReactiveCocoa

public enum UICollectionViewSupplementaryViewKind: RawRepresentable {
	case header
	case footer

	public var rawValue: String {
		switch self {
		case .header:
			return UICollectionElementKindSectionHeader
		case .footer:
			return UICollectionElementKindSectionFooter
		}
	}

	public init(rawValue: String) {
		switch rawValue {
		case UICollectionElementKindSectionHeader:
			self = .header
		case UICollectionElementKindSectionFooter:
			self = .footer
		default:
			fatalError()
		}
	}
}

public protocol UICollectionViewAdapterProvider: class {
	func cellForItem(at indexPath: IndexPath) -> UICollectionViewCell
	func supplementaryView(of category: UICollectionViewSupplementaryViewKind, at indexPath: IndexPath) -> UICollectionReusableView
}

final public class UICollectionViewAdapter<V: ViewModel, Provider: UICollectionViewAdapterProvider>: NSObject, UICollectionViewDataSource {
	private let set: ViewModelMappingSet<V>
	private let provider: Provider

	public init(set: ViewModelMappingSet<V>, provider: Provider) {
		self.set = set
		self.provider = provider
	}

	public func numberOfSections(in collectionView: UICollectionView) -> Int {
		return set.sectionCount
	}

	public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
		return provider.supplementaryView(of: UICollectionViewSupplementaryViewKind(rawValue: kind),
		                                  at: indexPath)
	}

	public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		return provider.cellForItem(at: indexPath)
	}

	public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return set.rowCount(for: section)
	}

	@discardableResult
	public static func bind(
		_ collectionView: UICollectionView,
		with set: ViewModelMappingSet<V>,
		provider: Provider
	) -> UICollectionViewAdapter<V, Provider> {
		let adapter = UICollectionViewAdapter(set: set, provider: provider)
		collectionView.dataSource = adapter
		collectionView.rac_lifetime.ended.observeCompleted { _ = adapter }

		defer { try! set.fetch() }

		set.eventsProducer
			.take(until: collectionView.willDeinitProducer)
			.startWithNext { [unowned collectionView] event in
				switch event {
				case .reloaded:
					collectionView.reloadData()

				case let .updated(changes):
					func updater() {
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
					}
					collectionView.performBatchUpdates(updater, completion: nil)
				}
			}

		return adapter
	}
}
