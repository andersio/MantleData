//
//  ReactiveSetEvent.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

/// Events of ReactiveSet

public enum ReactiveCollectionEvent {
	case reloaded
	case updated(ReactiveCollectionChanges)

	public init(clamping event: SectionedCollectionEvent, forSection index: Int) {
		switch event {
		case .reloaded:
			self = .reloaded

		case let .updated(changes):
			self = .updated(ReactiveCollectionChanges(clamping: changes, forSection: index))
		}
	}
}

/// Change Descriptor of ReactiveSet

public struct ReactiveCollectionChanges {
	public var deletedRows: [Int]?
	public var insertedRows: [Int]?
	public var movedRows: [(from: Int, to: Int)]?

	public init(clamping changes: SectionedCollectionChanges, forSection index: Int) {
		deletedRows = changes.deletedRows?.flatMap { $0.section == index ? $0.row : nil }
		insertedRows = changes.insertedRows?.flatMap { $0.section == index ? $0.row : nil }

		if let pairs = changes.movedRows {
			var movedRows = [(from: Int, to: Int)]()
			var _insertedRows = [Int]()
			var _deletedRows = [Int]()

			for (from, to) in pairs {
				if from.section == index && to.section == index {
					movedRows.append((from.row, to.row))
				} else if from.section == index {
					_deletedRows.append(to.row)
				} else if to.section == index {
					_insertedRows.append(to.row)
				}
			}

			if !_insertedRows.isEmpty {
				insertedRows = insertedRows.map { $0 + _insertedRows } ?? _insertedRows
			}

			if !_deletedRows.isEmpty {
				deletedRows = deletedRows.map { $0 + _deletedRows } ?? _deletedRows
			}
		}
	}
}

/// Events of ReactiveSet

public enum SectionedCollectionEvent {
	case reloaded
	case updated(SectionedCollectionChanges)
}

/// Change Descriptor of ReactiveSet

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
