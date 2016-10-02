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
	public var deletedRows: [IndexPath]?
	public var insertedRows: [IndexPath]?
	public var movedRows: [(from: IndexPath, to: IndexPath)]?

	public var deletedSections: IndexSet?
	public var insertedSections: IndexSet?
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

		if let indexPaths = insertedRows {
			strings.append("> \(indexPaths.count) row(s) inserted\n")
		}

		if let indexPaths = deletedRows {
			strings.append( "> \(indexPaths.count) row(s) deleted\n")
		}

		if let indexPaths = movedRows {
			strings.append( "> \(indexPaths.count) row(s) moved\n")
		}

		if let indices = insertedSections {
			strings.append("> \(indices.count) section(s) inserted\n")
		}

		if let indices = deletedSections {
			strings.append( "> \(indices.count) section(s) deleted\n")
		}

		return strings.joined(separator: "\n")
	}
}

extension SectionedCollectionChanges: CustomDebugStringConvertible {
	public var debugDescription: String {
		return description
	}
}
