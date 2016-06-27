//
//  ExistentialCollections.swift
//  MantleData
//
//  Created by Anders on 24/6/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// `AnyReactiveSet` assumes the wrapping ReactiveSet always uniformly index
/// its elements with 1 unit of distance in integer.
public struct AnyQueryableReactiveSet<E>: QueryableReactiveSet {
	public typealias Index = Int
	public typealias Section = AnyReactiveSetSection<E>

	private let set: _AnyReactiveSetBox<E>

	public init<R: QueryableReactiveSet where R.Iterator.Element: ReactiveSetSection, R.Section == R.Iterator.Element, R.Section.Iterator.Element == E>(_ set: R) {
		self.set = _AnyQueryableReactiveSetBoxBase(set)
	}

	public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	public var startIndex: Int {
		return set.startIndex
	}

	public var endIndex: Int {
		return set.endIndex
	}

	public var elementsCount: Int {
		return set.elementsCount
	}

	public func fetch(trackingChanges shouldTrackChanges: Bool) throws {
		try set.fetch(trackingChanges: shouldTrackChanges)
	}

	public subscript(index: Int) -> AnyReactiveSetSection<E> {
		return set[index]
	}

	public subscript(subRange: Range<Index>) -> BidirectionalSlice<AnyQueryableReactiveSet<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func makeIterator() -> IndexingIterator<AnyQueryableReactiveSet<E>> {
		return IndexingIterator(_elements: self)
	}

	public func index(after i: Int) -> Int {
		return set.index(after: i)
	}

	public func index(before i: Int) -> Int {
		return set.index(before: i)
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	public func indexPath(of element: Section.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
	}
}

public struct AnyReactiveSet<E>: ReactiveSet {
	public typealias Index = Int
	public typealias Section = AnyReactiveSetSection<E>

	private let set: _AnyReactiveSetBox<E>

	public init<R: ReactiveSet where R.Iterator.Element: ReactiveSetSection, R.Section == R.Iterator.Element, R.Section.Iterator.Element == E>(_ set: R) {
		self.set = _AnyReactiveSetBoxBase(set)
	}

	public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	public var startIndex: Int {
		return set.startIndex
	}

	public var endIndex: Int {
		return set.endIndex
	}

	public var elementsCount: Int {
		return set.elementsCount
	}

	public func fetch(trackingChanges shouldTrackChanges: Bool) throws {
		try set.fetch(trackingChanges: shouldTrackChanges)
	}

	public subscript(index: Int) -> AnyReactiveSetSection<E> {
		return set[index]
	}

	public subscript(subRange: Range<Index>) -> BidirectionalSlice<AnyReactiveSet<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func makeIterator() -> IndexingIterator<AnyReactiveSet<E>> {
		return IndexingIterator(_elements: self)
	}

	public func index(after i: Int) -> Int {
		return set.index(after: i)
	}

	public func index(before i: Int) -> Int {
		return set.index(before: i)
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	public func indexPath(of element: Section.Iterator.Element) -> IndexPath? {
		return set.indexPath(of: element)
	}
}

public struct AnyReactiveSetSection<E>: ReactiveSetSection {
	public typealias Index = Int

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

	public subscript(index: Index) -> E {
		return wrappedSection[index]
	}

	public subscript(subRange: Range<Index>) -> BidirectionalSlice<AnyReactiveSetSection<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func index(after i: Index) -> Index {
		return wrappedSection.index(after: i)
	}

	public func index(before i: Index) -> Index {
		return wrappedSection.index(before: i)
	}
}

public func == <Entity>(left: AnyReactiveSetSection<Entity>, right: AnyReactiveSetSection<Entity>) -> Bool {
	return left.name == right.name
}
