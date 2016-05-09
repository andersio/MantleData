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
///
/// - Note: Due to the one-way mapping requirement, `ViewModelSet` cannot conform to `ReactiveSet`.

public final class ViewModelSet<U: ViewModel> {
	internal var sectionNameMapper: (ReactiveSetSectionName -> ReactiveSetSectionName)?
  private let set: _AnyReactiveSetBox<U.MappingObject>
	internal let factory: U.MappingObject -> U
  
  public var eventProducer: SignalProducer<ReactiveSetEvent<AnyReactiveSetIndex, AnyReactiveSetIndex>, NoError> {
		return set.eventProducer
  }

	public init<R: ReactiveSet where R.Generator.Element.Generator.Element == U.MappingObject>(_ set: R, factory: U.MappingObject -> U) {
    self.set = _AnyReactiveSetBoxBase(set)
		self.factory = factory
	}

	public func fetch() throws {
		try set.fetch()
	}

	public func mapSectionName(using transform: ReactiveSetSectionName -> ReactiveSetSectionName) -> ViewModelSet {
		sectionNameMapper = transform
		return self
	}

	public var objectCount: Int {
		return set.objectCount
	}
}

extension ViewModelSet: CollectionType {
	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyGenerator<ViewModelSetSection<U>>

	public var startIndex: Index {
		return set.startIndex
	}

	public var endIndex: Index {
		return set.endIndex
	}

	public subscript(position: Index) -> Generator.Element {
		return ViewModelSetSection(set[position], in: self)
	}

	public func generate() -> Generator {
		var iterator = startIndex
		let limit = endIndex
		return AnyGenerator {
			defer { iterator = iterator.successor() }
			return iterator < limit ? self[iterator] : nil
		}
	}
}