//
//  AnyReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final public class AnyReactiveSet<E: Equatable> {
	private let set: _AnyReactiveSetBox<E>

	public init<R: ReactiveSet where R.Generator.Element.Generator.Element == E>(_ set: R) {
		self.set = _AnyReactiveSetBoxBase(set)
	}
}

extension AnyReactiveSet: ReactiveSet {
	public typealias Section = AnyReactiveSetSection<E>

	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyReactiveSetIterator<Section>
	public typealias SubSequence = AnyReactiveSetSlice<E>

	// Indexable

	public var startIndex: Index {
		return set.startIndex
	}

	public var endIndex: Index {
		return set.endIndex
	}

	public subscript(index: Index) -> Section {
		return set[index]
	}

	// SequenceType

	public func generate() -> Generator {
		return set.generate()
	}

	// CollectionType

	public subscript(bounds: Range<Index>) -> SubSequence {
		return set[bounds]
	}

	// ReactiveSet

	public var eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError> {
		return set.eventProducer
	}

	public func fetch() throws {
		try set.fetch()
	}

	public func sectionName(of object: E) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}
}

public struct AnyReactiveSetSection<E: Equatable> {
	public let name: ReactiveSetSectionName
	private let storage: _AnyReactiveSetSectionBox<E>

	public init<S: ReactiveSetSection where S.Generator.Element == E>(_ section: S) {
		name = section.name
		storage = _AnyReactiveSetSectionBoxBase(section)
	}
}

extension AnyReactiveSetSection: ReactiveSetSection {
	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyReactiveSetSectionIterator<E>
	public typealias SubSequence = AnyReactiveSetSectionSlice<E>

	// Indexable

	public var startIndex: Index {
		return storage.startIndex
	}

	public var endIndex: Index {
		return storage.endIndex
	}

	public subscript(index: Index) -> Generator.Element {
		return storage[index]
	}

	// SequenceType

	public func generate() -> Generator {
		return storage.generate()
	}

	// CollectionType

	public subscript(bounds: Range<Index>) -> SubSequence {
		return storage[bounds]
	}
}

public func == <Entity>(left: AnyReactiveSetSection<Entity>, right: AnyReactiveSetSection<Entity>) -> Bool {
	return left.name == right.name
}

public struct AnyReactiveSetSlice<E: Equatable>: CollectionType {
	public typealias _Element = AnyReactiveSetSection<E>

	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyReactiveSetIterator<AnyReactiveSetSection<E>>
	public typealias SubSequence = AnyReactiveSetSlice<E>

	private let set: _AnyReactiveSetBox<E>
	private let bounds: Range<Index>

	internal init(base set: _AnyReactiveSetBox<E>, bounds: Range<AnyReactiveSetIndex>) {
		self.set = set
		self.bounds = bounds
	}

	public var startIndex: Index {
		return bounds.startIndex
	}

	public var endIndex: Index {
		return bounds.endIndex
	}

	public func generate() -> Generator {
		var index = bounds.startIndex
		return AnyReactiveSetIterator {
			if index < self.bounds.endIndex {
				defer { index = index.successor() }
				return self.set[index]
			} else {
				return nil
			}
		}
	}

	public subscript(index: Index) -> Generator.Element {
		assert(index >= startIndex && index < endIndex, "Accessing a slice with an out of bound index.")
		return set[index]
	}

	public subscript(subRange: Range<Index>) -> SubSequence {
		assert(subRange.startIndex >= startIndex && subRange.endIndex <= endIndex, "Accessing a slice with an out of bound range.")
		return set[subRange]
	}
}


public struct AnyReactiveSetSectionSlice<E: Equatable>: CollectionType {
	public typealias Index = AnyReactiveSetIndex
	public typealias Generator = AnyGenerator<E>
	public typealias SubSequence = AnyReactiveSetSectionSlice<E>

	private let set: _AnyReactiveSetSectionBox<E>
	private let bounds: Range<AnyReactiveSetIndex>

	internal init(base set: _AnyReactiveSetSectionBox<E>, bounds: Range<AnyReactiveSetIndex>) {
		self.set = set
		self.bounds = bounds
	}

	public var startIndex: Index {
		return bounds.startIndex
	}

	public var endIndex: Index {
		return bounds.endIndex
	}

	public func generate() -> Generator {
		var index = bounds.startIndex
		return AnyGenerator {
			if index < self.bounds.endIndex {
				defer { index = index.successor() }
				return self.set[index]
			} else {
				return nil
			}
		}
	}

	public subscript(index: Index) -> Generator.Element {
		assert(index >= startIndex && index < endIndex, "Accessing a slice with an out of bound index.")
		return set[index]
	}

	public subscript(subRange: Range<Index>) -> SubSequence {
		assert(subRange.startIndex >= startIndex && subRange.endIndex <= endIndex, "Accessing a slice with an out of bound range.")
		return set[subRange]
	}
}