//
//  ViewModelSet.swift
//  MantleData
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import ReactiveCocoa

/// `ViewModelSet` is a type-erased collection view to a `ReactiveSet` implementation, which
/// maps view models of type `U` from the underlying set of `U.MappingObject` objects.
public struct ViewModelMappingSet<U: ViewModel>: ReactiveSet {
	public typealias Index = Int
	public typealias Section = ViewModelMappingSetSection<U>

	internal var sectionNameMapper: ((ReactiveSetSectionName) -> ReactiveSetSectionName)?
  private let set: _AnyReactiveSetBox<U.MappingObject>
	internal let factory: (U.MappingObject) -> U

	public var startIndex: Index {
		return set.startIndex
	}

	public var endIndex: Index {
		return set.endIndex
	}

  public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
	}

	public var elementsCount: Int {
		return set.elementsCount
	}

	public init<R: ReactiveSet where R.Iterator.Element: ReactiveSetSection, R.Section == R.Iterator.Element, R.Iterator.Element.Iterator.Element == U.MappingObject>(_ set: R, factory: (U.MappingObject) -> U) {
    self.set = _AnyReactiveSetBoxBase(set)
		self.factory = factory
	}

	public func fetch(trackingChanges shouldTrackChanges: Bool = false) throws {
		try set.fetch(trackingChanges: shouldTrackChanges)
	}

	public func mapSectionName(_ transform: (ReactiveSetSectionName) -> ReactiveSetSectionName) -> ViewModelMappingSet {
		var copy = self
		copy.sectionNameMapper = transform
		return copy
	}

	public subscript(position: IndexPath) -> U {
		return factory(set[position.section][position.row])
	}

	public subscript(position: Index) -> ViewModelMappingSetSection<U> {
		return ViewModelMappingSetSection(base: set[position], factory: factory, sectionNameTransform: sectionNameMapper)
	}

	public subscript(subRange: Range<Index>) -> BidirectionalSlice<ViewModelMappingSet<U>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func index(after i: Index) -> Index {
		return set.index(after: i)
	}

	public func index(before i: Index) -> Index {
		return set.index(before: i)
	}
}
