//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final internal class _AnyReactiveSetBoxBase<R: ReactiveSet>: _AnyReactiveSetBox<R.Iterator.Element.Iterator.Element> {
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
		return Index(converting: set.startIndex)
	}

	override var endIndex: Index {
		return Index(converting: set.endIndex)
	}

	override subscript(index: Index) -> AnyReactiveSetSection<R.Iterator.Element.Iterator.Element> {
		let index = R.Index(converting: index)
		return AnyReactiveSetSection(set[index])
	}

	override func makeIterator() -> Iterator {
		var i = self.startIndex
		return AnyReactiveSetIterator {
			if i < self.endIndex {
				defer { i = (i + 1) }
				return self[i]
			} else {
				return nil
			}
		}
	}

	override func index(after i: Index) -> Index {
		return Index(converting: set.index(after: R.Index(converting: i)))
	}

	override func sectionName(of object: Iterator.Element.Iterator.Element) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	override func indexPath(of element: Iterator.Element.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
	}
}

internal class _AnyReactiveSetBox<E>: ReactiveSet {
	typealias Index = Int
	typealias Iterator = AnyReactiveSetIterator<AnyReactiveSetSection<E>>

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		_abstractMethod_subclassMustImplement()
	}

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	func fetch(startTracking: Bool) throws {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> AnyReactiveSetSection<E> {
		_abstractMethod_subclassMustImplement()
	}

	func makeIterator() -> Iterator {
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
		return Index(converting: wrappedSection.startIndex)
	}

	override var endIndex: Index {
		return Index(converting: wrappedSection.endIndex)
	}

	init(_ set: S) {
		self.wrappedSection = set
	}

	override subscript(index: Index) -> S.Iterator.Element {
		let index = S.Index(converting: index)
		return wrappedSection[index]
	}

	override func makeIterator() -> Iterator {
		var i = self.startIndex
		return AnyReactiveSetSectionIterator {
			if i < self.endIndex {
				defer { i = (i + 1) }
				return self[i]
			}
			return nil
		}
	}

	override func index(after i: Index) -> Index {
		return Index(converting: wrappedSection.index(after: S.Index(converting: i)))
	}
}

internal class _AnyReactiveSetSectionBox<E>: ReactiveSetSection {
	typealias Entity = E

	typealias Index = Int
	typealias Iterator = AnyReactiveSetSectionIterator<E>

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

	func makeIterator() -> Iterator {
		_abstractMethod_subclassMustImplement()
	}

	func index(after i: Index) -> Index {
		_abstractMethod_subclassMustImplement()
	}

	func index(before i: Index) -> Index {
		_abstractMethod_subclassMustImplement()
	}
}
