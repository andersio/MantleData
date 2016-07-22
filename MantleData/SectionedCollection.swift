//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

public protocol SectionedCollectionIndex: Comparable {
	var section: Int { get }
	var row: Int { get }

	init<I: SectionedCollectionIndex>(_ index: I)
}

extension IndexPath: SectionedCollectionIndex {
	public init<I: SectionedCollectionIndex>(_ index: I) {
		self.init(row: index.row, section: index.section)
	}
}

public protocol SectionedCollection: class, BidirectionalCollection {
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
}
