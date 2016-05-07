//
//  AnyReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final public class AnyReactiveSet<E> {
	private let set: _AnyReactiveSetBox<E>

	public init<R: ReactiveSet where R.Generator.Element.Generator.Element == E>(_ set: R) {
		self.set = _AnyReactiveSetBoxBase(set)
	}
}

extension AnyReactiveSet: ReactiveSet {
	public typealias Section = AnyReactiveSetSection<E>

	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyReactiveSetIterator<Section>

	public var eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError> {
		return set.eventProducer
	}

	public var startIndex: Index {
		return set.startIndex
	}

	public var endIndex: Index {
		return set.endIndex
	}

	public func fetch() throws {
		try set.fetch()
	}

	public subscript(index: Index) -> Section {
		return set[index]
	}

	public func generate() -> Generator {
		return set.generate()
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	public func indexPath(of element: Generator.Element.Generator.Element) -> ReactiveSetIndexPath<Index, Generator.Element.Index>? {
		return set.indexPath(of: element)
	}
}

public struct AnyReactiveSetSection<E> {
	private let wrappedSection: _AnyReactiveSetSectionBox<E>

	public init<S: ReactiveSetSection where S.Generator.Element == E>(_ section: S) {
		wrappedSection = _AnyReactiveSetSectionBoxBase(section)
	}
}

extension AnyReactiveSetSection: ReactiveSetSection {
	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyReactiveSetSectionIterator<E>

	public var name: ReactiveSetSectionName {
		return wrappedSection.name
	}

	public var startIndex: Index {
		return wrappedSection.startIndex
	}

	public var endIndex: Index {
		return wrappedSection.endIndex
	}

	public subscript(index: Index) -> Generator.Element {
		return wrappedSection[index]
	}

	public func generate() -> Generator {
		return wrappedSection.generate()
	}
}

public func == <Entity>(left: AnyReactiveSetSection<Entity>, right: AnyReactiveSetSection<Entity>) -> Bool {
	return left.name == right.name
}