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

	public init<R: ReactiveSet where R.Iterator.Element.Iterator.Element == E>(_ set: R) {
		self.set = _AnyReactiveSetBoxBase(set)
	}
}

extension AnyReactiveSet: ReactiveSet {
	public typealias Index = Int
	public typealias IndexDistance = Int
	public typealias Iterator = AnyReactiveSetIterator<AnyReactiveSetSection<E>>
	public typealias Indices = CountableRange<Index>

	public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	public var startIndex: Index {
		return set.startIndex
	}

	public var endIndex: Index {
		return set.endIndex
	}

	public var indices: CountableRange<Index> {
		return startIndex ..< endIndex
	}

	public func fetch(startTracking: Bool) throws {
		try set.fetch(startTracking: startTracking)
	}

	public subscript(index: Index) -> AnyReactiveSetSection<E> {
		return set[index]
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}

	public func makeIterator() -> Iterator {
		return set.makeIterator()
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	public func indexPath(of element: Iterator.Element.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
	}
}

public struct AnyReactiveSetSection<E> {
	private let wrappedSection: _AnyReactiveSetSectionBox<E>

	public init<S: ReactiveSetSection where S.Iterator.Element == E>(_ section: S) {
		wrappedSection = _AnyReactiveSetSectionBoxBase(section)
	}
}

extension AnyReactiveSetSection: ReactiveSetSection {
	public typealias Index = Int
	public typealias Iterator = AnyReactiveSetSectionIterator<E>

	public var name: ReactiveSetSectionName {
		return wrappedSection.name
	}

	public var startIndex: Index {
		return wrappedSection.startIndex
	}

	public var endIndex: Index {
		return wrappedSection.endIndex
	}

	public subscript(index: Index) -> Iterator.Element {
		return wrappedSection[index]
	}

	public func makeIterator() -> Iterator {
		return wrappedSection.makeIterator()
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}
}

public func == <Entity>(left: AnyReactiveSetSection<Entity>, right: AnyReactiveSetSection<Entity>) -> Bool {
	return left.name == right.name
}
