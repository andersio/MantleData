//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

internal class _AnyQueryableReactiveSetBoxBase<R: QueryableReactiveSet where R.Iterator.Element: ReactiveSetSection, R.Section.Iterator.Element == R.Iterator.Element.Iterator.Element>: _AnyReactiveSetBoxBase<R> {
	override init(_ set: R) {
		super.init(set)
	}

	override func sectionName(of object: Section.Iterator.Element) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	override func indexPath(of element: Section.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
	}
}

internal class _AnyReactiveSetBoxBase<R: ReactiveSet where R.Iterator.Element: ReactiveSetSection, R.Section.Iterator.Element == R.Iterator.Element.Iterator.Element>: _AnyReactiveSetBox<R.Section.Iterator.Element> {
	private let set: R
	private let uniformDistance: Int

	override var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	init(_ set: R) {
		self.set = set
		self.uniformDistance = Int(R.uniformDistance.toIntMax())
	}

	override func fetch(trackingChanges shouldTrackChanges: Bool) throws {
		try set.fetch(trackingChanges: shouldTrackChanges)
	}

	override var startIndex: Index {
		return Int(unsafeCasting: set.startIndex)
	}

	override var endIndex: Index {
		return Int(unsafeCasting: set.endIndex)
	}

	override var elementsCount: Int {
		return Int(unsafeCasting: set.elementsCount)
	}

	override subscript(index: Index) -> AnyReactiveSetSection<R.Section.Iterator.Element> {
		let index = set.index(set.startIndex, offsetBy: R.IndexDistance(index.toIntMax()))
		return AnyReactiveSetSection(set[index])
	}

	override func index(after i: Index) -> Index {
		return i + uniformDistance
	}

	override func index(before i: Index) -> Index {
		return i - uniformDistance
	}
}

internal class _AnyReactiveSetBox<E> {
	typealias Index = Int
	typealias Section = AnyReactiveSetSection<E>

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		_abstractMethod_subclassMustImplement()
	}

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var elementsCount: Int {
		_abstractMethod_subclassMustImplement()
	}

	func fetch(trackingChanges shouldTrackChanges: Bool) throws {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> AnyReactiveSetSection<E> {
		_abstractMethod_subclassMustImplement()
	}

	subscript(subRange: Range<Index>) -> BidirectionalSlice<AnyBidirectionalCollection<E>> {
		_abstractMethod_subclassMustImplement()
	}

	func index(after i: Index) -> Index {
		_abstractMethod_subclassMustImplement()
	}

	func index(before i: Index) -> Index {
		_abstractMethod_subclassMustImplement()
	}

	func sectionName(of object: E) -> ReactiveSetSectionName? {
		_abstractMethod_subclassMustImplement()
	}

	func indexPath(of element: E) -> IndexPath? {
		_abstractMethod_subclassMustImplement()
	}
}

final internal class _AnyReactiveSetSectionBoxBase<S: ReactiveSetSection>: _AnyReactiveSetSectionBox<S.Iterator.Element> {
	private let base: S
	private let uniformDistance: Int

	override var name: ReactiveSetSectionName {
		return base.name
	}

	override var startIndex: Index {
		return Int(unsafeCasting: base.startIndex)
	}

	override var endIndex: Index {
		return Int(unsafeCasting: base.endIndex)
	}

	init(_ set: S) {
		self.base = set
		self.uniformDistance = Int(unsafeCasting: S.uniformDistance)
	}

	override subscript(index: Index) -> S.Iterator.Element {
		let index = base.index(base.startIndex, offsetBy: S.IndexDistance(index.toIntMax()))
		return base[index]
	}

	override func index(after i: Index) -> Index {
		return i + uniformDistance
	}

	override func index(before i: Index) -> Index {
		return i - uniformDistance
	}
}

internal class _AnyReactiveSetSectionBox<E> {
	typealias Index = Int

	var name: ReactiveSetSectionName {
		_abstractMethod_subclassMustImplement()
	}

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> E {
		_abstractMethod_subclassMustImplement()
	}

	func index(after i: Index) -> Index {
		_abstractMethod_subclassMustImplement()
	}

	func index(before i: Index) -> Index {
		_abstractMethod_subclassMustImplement()
	}
}
