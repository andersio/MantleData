//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveSwift
import enum Result.NoError

public protocol SectionedCollection: class, RandomAccessCollection {
	associatedtype Index: SectionedCollectionIndex = IndexPath

	var events: Signal<SectionedCollectionEvent, NoError> { get }
	var sectionCount: Int { get }

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
