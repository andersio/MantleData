//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift

public protocol SectionedCollectionIndex: Comparable {
	var section: Int { get }
	var row: Int { get }

	init<I: SectionedCollectionIndex>(_ index: I)
	init(row: Int, section: Int)
}

extension IndexPath: SectionedCollectionIndex {
	public init<I: SectionedCollectionIndex>(_ index: I) {
		self.init(row: index.row, section: index.section)
	}
}

public protocol ReactiveCollection: class, RandomAccessCollection {
	var events: Signal<ReactiveCollectionEvent, NoError> { get }

	func fetch(trackingChanges: Bool) throws
}

public protocol SectionedCollection: class, RandomAccessCollection {
	associatedtype Index: SectionedCollectionIndex = IndexPath

	var events: Signal<SectionedCollectionEvent, NoError> { get }
	var sectionCount: Int { get }

	func fetch(trackingChanges: Bool) throws

	func sectionName(for section: Int) -> String?
	func rowCount(for section: Int) -> Int
}

extension SectionedCollection {
	public var eventsProducer: SignalProducer<SectionedCollectionEvent, NoError> {
		return SignalProducer(signal: events)
	}

	public subscript(section section: Int, row row: Int) -> Iterator.Element {
		return self[Index(row: row, section: section)]
	}
}
