//
//  CollectionViewAdapter+UIKit.swift
//  MantleData
//
//  Created by Anders on 14/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import UIKit
import ReactiveSwift

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

final public class UICollectionViewAdapter<ViewModel, Provider: UICollectionViewAdapterProvider>: NSObject, UICollectionViewDataSource {
	private let set: ViewModelCollection<ViewModel>
	private let provider: Provider
	public let disposable: Disposable

	public init(set: ViewModelCollection<ViewModel>, provider: Provider, disposable: Disposable) {
		self.set = set
		self.provider = provider
		self.disposable = disposable

		super.init()
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
		with set: ViewModelCollection<ViewModel>,
		provider: Provider
	) -> UICollectionViewAdapter<ViewModel, Provider> {
		let disposable = CompositeDisposable()

		let adapter = UICollectionViewAdapter(set: set,
		                                      provider: provider,
		                                      disposable: disposable)
		collectionView.dataSource = adapter

		disposable += set.events
			.take(during: collectionView.reactive.lifetime)
			.observeValues { [adapter, weak collectionView] event in
				guard let collectionView = collectionView else { return }

				switch event {
				case .reloaded:
					collectionView.reloadData()

				case let .updated(changes):
					func update() {
						collectionView.deleteSections(changes.deletedSections)
						collectionView.deleteItems(at: changes.deletedRows)
						collectionView.insertSections(changes.insertedSections)
						collectionView.insertItems(at: changes.insertedRows)

						for (source, destination) in changes.movedRows {
							collectionView.moveItem(at: source, to: destination)
						}
					}
					collectionView.performBatchUpdates(update, completion: nil)
				}
			}

		return adapter
	}
}
