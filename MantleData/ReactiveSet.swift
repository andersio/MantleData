//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// ReactiveSet
public protocol ReactiveSet: class, BidirectionalCollection {
	associatedtype Section: ReactiveSetSection

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> { get }
	var elementsCount: IndexDistance { get }

	func fetch(startTracking: Bool) throws
	func sectionName(of element: Section.Iterator.Element) -> ReactiveSetSectionName?
	func indexPath(of element: Section.Iterator.Element) -> IndexPath?
}

extension ReactiveSet where Iterator.Element: ReactiveSetSection, Iterator.Element == Section {
	public subscript(index: Int) -> Section {
		let offset = IndexDistance(index.toIntMax())
		let convertedIndex = self.index(startIndex, offsetBy: offset)
		return self[convertedIndex]
	}

	public subscript(name: ReactiveSetSectionName) -> Section? {
		if let index = index(of: name) {
			return self[index]
		}

		return nil
	}

	public subscript(indexPath: IndexPath) -> Section.Iterator.Element {
		let sectionOffset = IndexDistance(indexPath.section.toIntMax())
		let sectionIndex = self.index(startIndex, offsetBy: sectionOffset)

		let rowOffset = Section.IndexDistance(indexPath.row.toIntMax())
		let rowIndex = self[sectionIndex].index(self[sectionIndex].startIndex, offsetBy: rowOffset)

		return self[sectionIndex][rowIndex]
	}

	public var objectCount: Section.IndexDistance {
		return reduce(0, combine: { $0 + $1.count })
	}

	public func fetch() throws {
		try fetch(startTracking: false)
	}

	public func index(of name: ReactiveSetSectionName) -> Index? {
		return self.index { $0.name == name }
	}
}
