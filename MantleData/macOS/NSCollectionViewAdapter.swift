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

@available(macOS 10.11, *)
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

@available(macOS 10.11, *)
public struct NSCollectionViewAdapterConfig {
	// Workaround: Empty struct somehow crashes Swift runtime.
	public var placeholder = true
	public init() {}
}

@available(macOS 10.11, *)
public protocol NSCollectionViewAdapterProvider: class {
	func item(at indexPath: IndexPath) -> NSCollectionViewItem
	func supplementaryView(of kind: NSCollectionViewSupplementaryViewKind, at indexPath: IndexPath) -> NSView
}

@available(macOS 10.11, *)
public final class NSCollectionViewAdapter<ViewModel, Provider: NSCollectionViewAdapterProvider>: NSObject, NSCollectionViewDataSource {
	private let set: ViewModelCollection<ViewModel>
	private unowned let provider: Provider
	private let config: NSCollectionViewAdapterConfig
	public let disposable: Disposable

	public init(set: ViewModelCollection<ViewModel>, provider: Provider, config: NSCollectionViewAdapterConfig, disposable: Disposable) {
		self.set = set
		self.provider = provider
		self.config = config
		self.disposable = disposable

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
		with set: ViewModelCollection<ViewModel>,
		provider: Provider,
		config: NSCollectionViewAdapterConfig
	) -> NSCollectionViewAdapter<ViewModel, Provider> {
		let disposable = CompositeDisposable()

		let adapter = NSCollectionViewAdapter<ViewModel, Provider>(set: set,
		                                                   provider: provider,
		                                                   config: config,
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
						collectionView.deleteItems(at: Set(changes.deletedRows))
						collectionView.insertSections(changes.insertedSections)
						collectionView.insertItems(at: Set(changes.insertedRows))
						collectionView.reloadItems(at: Set(changes.updatedRows))

						for (origin, destination) in changes.movedRows {
							collectionView.moveItem(at: origin, to: destination)
						}
					}

					collectionView.animator().performBatchUpdates(update, completionHandler: nil)
				}
			}

		return adapter
	}
}
