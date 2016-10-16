//
//  ReactiveSetEvent.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

/// An change event of a `SectionedCollection`.
public enum SectionedCollectionEvent {
	case reloaded
	case updated(SectionedCollectionChanges)
}

/// Describes the changes in a `SectionedCollection` of a particular event.
public struct SectionedCollectionChanges {
	public var deletedRows: [IndexPath]
	public var insertedRows: [IndexPath]
	public var updatedRows: [IndexPath]
	public var movedRows: [(from: IndexPath, to: IndexPath)]

	public var deletedSections: IndexSet
	public var insertedSections: IndexSet
}

extension SectionedCollectionEvent: CustomStringConvertible {
	public var description: String {
		switch self {
		case .reloaded:
			return "ReactiveSetEvent.Reloaded"

		case let .updated(changes):
			return "ReactiveSetEvent.Updated [BEGIN]\n\(changes)\n[END]"
		}
	}
}

extension SectionedCollectionEvent: CustomDebugStringConvertible {
	public var debugDescription: String {
		return description
	}
}

extension SectionedCollectionChanges: CustomStringConvertible {
	public var description: String {
		var strings = [String]()

		strings.append("SectionedReactiveCollectionChanges")
		strings.append("> \(insertedRows.count) row(s) inserted\n")
		strings.append("> \(deletedRows.count) row(s) deleted\n")
		strings.append("> \(movedRows.count) row(s) moved\n")
		strings.append("> \(insertedSections.count) section(s) inserted\n")
		strings.append("> \(deletedSections.count) section(s) deleted\n")

		return strings.joined(separator: "\n")
	}
}

extension SectionedCollectionChanges: CustomDebugStringConvertible {
	public var debugDescription: String {
		return description
	}
}
