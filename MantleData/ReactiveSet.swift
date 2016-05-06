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

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> { get }

	func fetch() throws
	func sectionName(of object: Object) -> ReactiveSetSectionName?
}

extension ReactiveSet {
	public typealias Object = Generator.Element.Generator.Element
	public typealias IndexPath = MantleData.IndexPath<Index, Generator.Element.Index>

	public var eventSignal: Signal<ReactiveSetEvent, NoError> {
		var extractedSignal: Signal<ReactiveSetEvent, NoError>!
		eventProducer.startWithSignal { signal, _ in
			extractedSignal = signal
		}
		return extractedSignal
	}

	public subscript(index: AnyReactiveSetIndex) -> Generator.Element {
		return self[Index(converting: index)]
	}

	public subscript(name: ReactiveSetSectionName) -> Generator.Element? {
		if let index = indexOfSection(with: name) {
			return self[index]
		}

		return nil
	}

	public subscript(indexPath: NSIndexPath) -> Generator.Element.Generator.Element {
		let section = self[Index(converting: indexPath.section)]
		return section[Generator.Element.Index(converting: indexPath.row)]
	}

	public func indexPath(of element: Object) -> IndexPath? {
		if let name = sectionName(of: element),
					 sectionIndex = indexOfSection(with: name),
					 objectIndex = self[sectionIndex].indexOf(element) {
			return IndexPath(section: sectionIndex, row: objectIndex)
		}

		return nil
	}
}

extension CollectionType where Generator.Element: ReactiveSetSection {
	public func indexOfSection(with name: ReactiveSetSectionName) -> Index? {
		return indexOf { $0.name == name }
	}
}
