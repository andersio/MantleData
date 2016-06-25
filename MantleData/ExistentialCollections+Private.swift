//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final internal class _AnyReactiveSetBoxBase<R: ReactiveSet where R.Iterator.Element: ReactiveSetSection, R.Section.Iterator.Element == R.Iterator.Element.Iterator.Element>: _AnyReactiveSetBox<R.Section.Iterator.Element> {
	private let set: R

	override var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	init(_ set: R) {
		self.set = set
	}

	override func fetch(startTracking: Bool) throws {
		try set.fetch(startTracking: startTracking)
	}

	override var startIndex: Index {
		return 0
	}

	override var endIndex: Index {
		return Int(set.count.toIntMax())
	}

	override var elementsCount: Int {
		return Int(set.elementsCount.toIntMax())
	}

	override subscript(index: Index) -> AnyReactiveSetSection<R.Section.Iterator.Element> {
		let index = set.index(set.startIndex, offsetBy: R.IndexDistance(index.toIntMax()))
		return AnyReactiveSetSection(set[index])
	}

	override func index(after i: Index) -> Index {
		return i + 1
	}

	override func index(before i: Index) -> Index {
		return i - 1
	}

	override func sectionName(of object: Section.Iterator.Element) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	override func indexPath(of element: Section.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
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

	func fetch(startTracking: Bool) throws {
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
	private let wrappedSection: S

	override var name: ReactiveSetSectionName {
		return wrappedSection.name
	}

	override var startIndex: Index {
		return 0
	}

	override var endIndex: Index {
		return Int(wrappedSection.count.toIntMax())
	}

	init(_ set: S) {
		self.wrappedSection = set
	}

	override subscript(index: Index) -> S.Iterator.Element {
		let index = wrappedSection.index(wrappedSection.startIndex, offsetBy: S.IndexDistance(index.toIntMax()))
		return wrappedSection[index]
	}

	override func index(after i: Index) -> Index {
		return i + 1
	}

	override func index(before i: Index) -> Index {
		return i - 1
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
