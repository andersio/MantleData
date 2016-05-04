//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final internal class _AnyReactiveSetBoxBase<R: ReactiveSet>: _AnyReactiveSetBox<R.Generator.Element.Generator.Element> {
	private let set: R

	init(_ set: R) {
		self.set = set
	}

	override var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	override func fetch() throws {
		try set.fetch()
	}

	override var startIndex: Index {
		return Index(reactiveSetIndex: set.startIndex)
	}

	override var endIndex: Index {
		return Index(reactiveSetIndex: set.endIndex)
	}

	override subscript(index: Index) -> AnyReactiveSetSection<R.Generator.Element.Generator.Element> {
		let index = R.Index(reactiveSetIndex: index)
		return AnyReactiveSetSection(set[index])
	}

	// SequenceType

	override func generate() -> Generator {
		var i = self.startIndex
		return AnyReactiveSetIterator {
			if i < self.endIndex {
				defer { i = i.successor() }
				return self[i]
			} else {
				return nil
			}
		}
	}

	override subscript(subRange: Range<AnyReactiveSetIndex>) -> AnyReactiveSetSlice<R.Generator.Element.Generator.Element> {
		return AnyReactiveSetSlice(base: self, bounds: subRange)
	}
}

internal class _AnyReactiveSetBox<E>: ReactiveSet {
	typealias Index = AnyReactiveSetIndex
	typealias Generator = AnyReactiveSetIterator<AnyReactiveSetSection<E>>
	typealias SubSequence = AnyReactiveSetSlice<E>

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		_abstractMethod_subclassMustImplement()
	}

	func fetch() throws {
		_abstractMethod_subclassMustImplement()
	}

	// Indexable

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> AnyReactiveSetSection<E> {
		_abstractMethod_subclassMustImplement()
	}

	// SequenceType

	func generate() -> Generator {
		_abstractMethod_subclassMustImplement()
	}

	subscript(subRange: Range<Index>) -> SubSequence {
		_abstractMethod_subclassMustImplement()
	}
}

final internal class _AnyReactiveSetSectionBoxBase<S: ReactiveSetSection>: _AnyReactiveSetSectionBox<S.Generator.Element> {
	private let set: S

	init(_ set: S) {
		self.set = set
	}

	override var startIndex: Index {
		return Index(reactiveSetIndex: set.startIndex)
	}

	override var endIndex: Index {
		return Index(reactiveSetIndex: set.endIndex)
	}

	override subscript(index: Index) -> S.Generator.Element {
		let index = S.Index(reactiveSetIndex: index)
		return set[index]
	}

	// SequenceType

	override func generate() -> Generator {
		var i = self.startIndex
		return AnyGenerator {
			if i < self.endIndex {
				defer { i = i.successor() }
				return self[i]
			}
			return nil
		}
	}

	override subscript(subRange: Range<AnyReactiveSetIndex>) -> AnyReactiveSetSectionSlice<S.Generator.Element> {
		return AnyReactiveSetSectionSlice(base: self, bounds: subRange)
	}
}

internal class _AnyReactiveSetSectionBox<E>: ReactiveSetSection {
	typealias Entity = E

	typealias Index = AnyReactiveSetIndex
	typealias Generator = AnyGenerator<E>
	typealias SubSequence = AnyReactiveSetSectionSlice<E>

	var name: ReactiveSetSectionName {
		_abstractMethod_subclassMustImplement()
	}

	// Indexable

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> E {
		_abstractMethod_subclassMustImplement()
	}

	// SequenceType

	func generate() -> Generator {
		_abstractMethod_subclassMustImplement()
	}

	subscript(subRange: Range<Index>) -> SubSequence {
		_abstractMethod_subclassMustImplement()
	}
}