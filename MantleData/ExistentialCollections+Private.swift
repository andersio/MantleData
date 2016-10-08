//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

internal class _ViewModelCollectionBoxBase<R: SectionedCollection, ViewModel>: _AnySectionedCollectionBox<ViewModel> {
	private let set: R
	private let factory: (R.Iterator.Element) -> ViewModel

	init(_ set: R, factory: @escaping (R.Iterator.Element) -> ViewModel) {
		self.set = set
		self.factory = factory
	}

	override var events: Signal<SectionedCollectionEvent, NoError> {
		return set.events
	}

	override var sectionCount: Int {
		return set.sectionCount
	}

	override var startIndex: Index {
		return IndexPath(set.startIndex)
	}

	override var endIndex: Index {
		return IndexPath(set.endIndex)
	}

	override func index(after i: Index) -> Index {
		return Index(set.index(after: R.Index(i)))
	}

	override func index(before i: Index) -> Index {
		return Index(set.index(before: R.Index(i)))
	}

	override subscript(indexPath: Index) -> ViewModel {
		return factory(set[R.Index(indexPath)])
	}

	override func sectionName(for section: Int) -> String? {
		return set.sectionName(for: section)
	}

	override func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}
}

internal class _AnySectionedCollectionBoxBase<R: SectionedCollection>: _AnySectionedCollectionBox<R.Iterator.Element> {
	private let set: R

	init(_ set: R) {
		self.set = set
	}

	override var events: Signal<SectionedCollectionEvent, NoError> {
		return set.events
	}

	override var sectionCount: Int {
		return set.sectionCount
	}

	override var startIndex: Index {
		return IndexPath(set.startIndex)
	}

	override var endIndex: Index {
		return IndexPath(set.endIndex)
	}

	override func index(after i: Index) -> Index {
		return Index(set.index(after: R.Index(i)))
	}

	override func index(before i: Index) -> Index {
		return Index(set.index(before: R.Index(i)))
	}

	override subscript(indexPath: Index) -> R.Iterator.Element {
		return set[R.Index(indexPath)]
	}

	override func sectionName(for section: Int) -> String? {
		return set.sectionName(for: section)
	}

	override func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}
}

internal class _AnySectionedCollectionBox<E> {
	typealias Index = IndexPath

	var events: Signal<SectionedCollectionEvent, NoError> { fatalError() }
	var sectionCount: Int { fatalError() }

	var startIndex: Index { fatalError() }
	var endIndex: Index { fatalError() }
	func index(after i: Index) -> Index { fatalError() }
	func index(before i: Index) -> Index { fatalError() }

	subscript(index: Index) -> E { fatalError() }

	func sectionName(for section: Int) -> String? { fatalError() }
	func rowCount(for section: Int) -> Int { fatalError() }
}
