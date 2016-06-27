//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// ReactiveSet represents a sectioned collection that can be observed for changes.
///
/// QueryableReactiveSet extends ReactiveSet to require the collection to be able
/// to reversely lookup the index path and the section name from any given element.
///
/// Implementations should uniformly index its elements with the distance specified
/// by `ReactiveSet.Type.uniformDistance`, which is 1 by default.

public protocol QueryableReactiveSet: ReactiveSet {
	func sectionName(of element: Section.Iterator.Element) -> ReactiveSetSectionName?
	func indexPath(of element: Section.Iterator.Element) -> IndexPath?
}

public protocol ReactiveSet: BidirectionalCollection {
	associatedtype Section: ReactiveSetSection
	associatedtype Index: SignedInteger

	static var uniformDistance: IndexDistance { get }

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> { get }
	var elementsCount: IndexDistance { get }

	func fetch(trackingChanges: Bool) throws
	func index(of name: ReactiveSetSectionName) -> Index?

	subscript(name: ReactiveSetSectionName) -> Section? { get }
	subscript(indexPath: IndexPath) -> Section.Iterator.Element { get }
}

extension ReactiveSet {
	public static var uniformDistance: IndexDistance {
		return 1
	}
}

extension ReactiveSet where Iterator.Element: ReactiveSetSection, Iterator.Element == Section {
	public func fetch() throws {
		try fetch(trackingChanges: false)
	}

	public func index(of name: ReactiveSetSectionName) -> Index? {
		return self.index { $0.name == name }
	}

	public subscript(name: ReactiveSetSectionName) -> Section? {
		if let index = index(of: name) {
			return self[index]
		}

		return nil
	}

	public subscript(indexPath: IndexPath) -> Section.Iterator.Element {
		let sectionIndex = Index(unsafeCasting: indexPath.section)
		let rowIndex = Section.Index(unsafeCasting: indexPath.row)

		return self[sectionIndex][rowIndex]
	}
}
