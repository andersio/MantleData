//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

internal class _LazyMapSectionedCollectionBase<R: SectionedCollection, U>: _AnySectionedCollectionBox<U> {
	private let set: R
	private let transform: (R.Iterator.Element) -> U

	init(_ set: R, transform: @escaping (R.Iterator.Element) -> U) {
		self.set = set
		self.transform = transform
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

	override subscript(row row: Int, section section: Int) -> U {
		let object = set[row: row, section: section]
		return transform(object)
	}

	override func sectionName(for section: Int) -> String? {
		return set.sectionName(for: section)
	}

	override func rowCount(for section: Int) -> Int {
		return set.rowCount(for: section)
	}
}

internal class _ViewModelCollectionBoxBase<R: SectionedCollection, ViewModel>: _AnySectionedCollectionBox<(ViewModel) -> Void> {
	private let set: R
	private let binder: (R.Iterator.Element, ViewModel) -> Void

	init(_ set: R, binder: @escaping (R.Iterator.Element, ViewModel) -> Void) {
		self.set = set
		self.binder = binder
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

	override subscript(row row: Int, section section: Int) -> (ViewModel) -> Void {
		let object = set[row: row, section: section]
		return { viewModel in self.binder(object, viewModel) }
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

	override subscript(row row: Int, section section: Int) -> R.Iterator.Element {
		return set[row: row, section: section]
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

	subscript(row row: Int, section section: Int) -> E { fatalError() }

	func sectionName(for section: Int) -> String? { fatalError() }
	func rowCount(for section: Int) -> Int { fatalError() }
}
