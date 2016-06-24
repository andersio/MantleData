//
//  ExistentialCollections.swift
//  MantleData
//
//  Created by Anders on 24/6/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final public class AnyReactiveSet<E>: ReactiveSet {
	public typealias Index = Int
	public typealias Iterator = DefaultReactiveSetIterator<AnyReactiveSetSection<E>>

	private let set: _AnyReactiveSetBox<E>

	public init<R: ReactiveSet where R.Iterator.Element.Iterator.Element == E>(_ set: R) {
		self.set = _AnyReactiveSetBoxBase(set)
	}

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

	public subscript(subRange: Range<Index>) -> BidirectionalSlice<AnyReactiveSet<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func makeIterator() -> Iterator {
		return set.makeIterator()
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	public func indexPath(of element: Iterator.Element.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
	}
}

public struct AnyReactiveSetSection<E>: ReactiveSetSection {
	public typealias Index = Int
	public typealias Iterator = AnyIterator<E>

	private let wrappedSection: _AnyReactiveSetSectionBox<E>

	public init<S: ReactiveSetSection where S.Iterator.Element == E>(_ section: S) {
		wrappedSection = _AnyReactiveSetSectionBoxBase(section)
	}

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

	public subscript(subRange: Range<Int>) -> BidirectionalSlice<AnyReactiveSetSection<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
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
