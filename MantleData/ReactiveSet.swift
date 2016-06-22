//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// ReactiveSet

public protocol ReactiveSetIterator: IteratorProtocol {
	associatedtype Element: ReactiveSetSection
}

public struct AnyReactiveSetIterator<S: ReactiveSetSection>: ReactiveSetIterator {
	public typealias Element = S

	private let generator: () -> Element?

	public init(generator: () -> Element?) {
		self.generator = generator
	}

	public mutating func next() -> Element? {
		return generator()
	}
}

public protocol ReactiveSet: class, Collection {
	associatedtype Iterator: ReactiveSetIterator
	associatedtype Index: ReactiveSetIndex

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> { get }

	func fetch(startTracking: Bool) throws
	func sectionName(of element: Generator.Element.Iterator.Element) -> ReactiveSetSectionName?
	func indexPath(of element: Generator.Element.Iterator.Element) -> IndexPath?
}

extension ReactiveSet {
	public subscript(index: Int) -> Iterator.Element {
		return self[Index(converting: index)]
	}

	public subscript(name: ReactiveSetSectionName) -> Iterator.Element? {
		if let index = indexOfSection(with: name) {
			return self[index]
		}

		return nil
	}

	public subscript(indexPath: IndexPath) -> Iterator.Element.Iterator.Element {
		return self[indexPath.section][Generator.Element.Index(converting: indexPath.row)]
	}

	public var objectCount: Iterator.Element.IndexDistance {
		return reduce(0, combine: { $0 + $1.count })
	}

	public func fetch() throws {
		try fetch(startTracking: false)
	}
}

extension ReactiveSet where Iterator.Element.Iterator.Element: Equatable {
	public func indexPath(of element: Iterator.Element.Iterator.Element) -> IndexPath? {
		if let name = sectionName(of: element),
			sectionIndex = indexOfSection(with: name),
			objectIndex = self[sectionIndex].index(of: element) {
			return IndexPath(row: objectIndex.toInt(), section: sectionIndex.toInt())
		}

		return nil
	}
}

extension Collection where Iterator.Element: ReactiveSetSection {
	public func indexOfSection(with name: ReactiveSetSectionName) -> Index? {
		return self.index { $0.name == name }
	}
}
