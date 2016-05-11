//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// ReactiveSet

public protocol ReactiveSetGenerator: GeneratorType {
	associatedtype Element: ReactiveSetSection
}

public struct AnyReactiveSetIterator<S: ReactiveSetSection>: ReactiveSetGenerator {
	public typealias Element = S

	private let generator: () -> Element?

	public init(generator: () -> Element?) {
		self.generator = generator
	}

	public mutating func next() -> Element? {
		return generator()
	}
}

public protocol ReactiveSet: class, CollectionType {
	associatedtype Generator: ReactiveSetGenerator
	associatedtype Index: ReactiveSetIndex

	var eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError> { get }

	func fetch() throws
	func sectionName(of element: Generator.Element.Generator.Element) -> ReactiveSetSectionName?
	func indexPath(of element: Generator.Element.Generator.Element) -> ReactiveSetIndexPath<Index, Generator.Element.Index>?
}

extension ReactiveSet {
	public subscript(index: AnyReactiveSetIndex) -> Generator.Element {
		return self[Index(converting: index)]
	}

	public subscript(name: ReactiveSetSectionName) -> Generator.Element? {
		if let index = indexOfSection(with: name) {
			return self[index]
		}

		return nil
	}

	public subscript(indexPath: ReactiveSetIndexPath<Index, Generator.Element.Index>) -> Generator.Element.Generator.Element {
		return self[indexPath.section][indexPath.row]
	}

	public var objectCount: Generator.Element.Index.Distance {
		return reduce(0, combine: { $0 + $1.count })
	}
}

extension ReactiveSet where Generator.Element.Generator.Element: Equatable {
	public func indexPath(of element: Generator.Element.Generator.Element) -> ReactiveSetIndexPath<Index, Generator.Element.Index>? {
		if let name = sectionName(of: element),
			sectionIndex = indexOfSection(with: name),
			objectIndex = self[sectionIndex].indexOf(element) {
			return ReactiveSetIndexPath(section: sectionIndex, row: objectIndex)
		}

		return nil
	}
}

extension CollectionType where Generator.Element: ReactiveSetSection {
	public func indexOfSection(with name: ReactiveSetSectionName) -> Index? {
		return indexOf { $0.name == name }
	}
}
