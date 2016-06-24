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

public struct DefaultReactiveSetSectionIterator<E>: IteratorProtocol {
	public typealias Element = E

	private let generator: () -> Element?

	public init<S: ReactiveSetSection where S.Iterator.Element == E>(for section: S, bounds: Range<S.Index>? = nil) {
		var bounds = bounds ?? section.startIndex ..< section.endIndex
		var index: S.Index? = bounds.lowerBound
		self.generator = {
			return index.map { currentIndex in
				defer { index = section.index(currentIndex, offsetBy: 1, limitedBy: bounds.upperBound) }
				return section[currentIndex]
			}
		}
	}

	public mutating func next() -> Element? {
		return generator()
	}
}

public struct DefaultReactiveSetIterator<S: ReactiveSetSection>: ReactiveSetIterator {
	public typealias Element = S

	private let generator: () -> Element?

	public init<R: ReactiveSet where R.Iterator.Element == S>(for set: R, bounds: Range<R.Index>? = nil) {
		var bounds = bounds ?? set.startIndex ..< set.endIndex
		var index: R.Index? = bounds.lowerBound
		self.generator = {
			return index.map { currentIndex in
				defer { index = set.index(currentIndex, offsetBy: 1, limitedBy: bounds.upperBound) }
				return set[currentIndex]
			}
		}
	}

	public mutating func next() -> Element? {
		return generator()
	}
}

public protocol ReactiveSet: class, BidirectionalCollection {
	associatedtype Iterator: ReactiveSetIterator
	associatedtype Index: ReactiveSetIndex

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> { get }

	func fetch(startTracking: Bool) throws
	func sectionName(of element: Iterator.Element.Iterator.Element) -> ReactiveSetSectionName?
	func indexPath(of element: Iterator.Element.Iterator.Element) -> IndexPath?
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
		return self[indexPath.section][Iterator.Element.Index(converting: indexPath.row)]
	}

	public var objectCount: Iterator.Element.IndexDistance {
		return reduce(0, combine: { $0 + $1.count })
	}

	public func fetch() throws {
		try fetch(startTracking: false)
	}
}

extension Collection where Iterator.Element: ReactiveSetSection {
	public func indexOfSection(with name: ReactiveSetSectionName) -> Index? {
		return self.index { $0.name == name }
	}
}
