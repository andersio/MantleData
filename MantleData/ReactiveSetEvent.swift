//
//  ReactiveSetEvent.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

/// Events of ReactiveSet

public enum ReactiveSetEvent {
	case reloaded
	case updated(ReactiveSetChanges)
}

/// Change Descriptor of ReactiveSet

public struct ReactiveSetChanges {
	public var deletedRows: [ReactiveSetIndexPath]?
	public var insertedRows: [ReactiveSetIndexPath]?
	public var movedRows: [(from: ReactiveSetIndexPath, to: ReactiveSetIndexPath)]?
	public var updatedRows: [ReactiveSetIndexPath]?

	public var insertedSections: [Int]?
	public var deletedSections: [Int]?
	public var reloadedSections: [Int]?

	public init(insertedRows: [ReactiveSetIndexPath]? = nil,
	            deletedRows: [ReactiveSetIndexPath]? = nil,
	            movedRows: [(from: ReactiveSetIndexPath, to: ReactiveSetIndexPath)]? = nil,
	            updatedRows: [ReactiveSetIndexPath]? = nil,
	            insertedSections: [Int]? = nil,
	            deletedSections: [Int]? = nil,
	            reloadedSections: [Int]? = nil) {
		self.insertedRows = insertedRows
		self.deletedRows = deletedRows
		self.movedRows = movedRows
		self.updatedRows = updatedRows

		self.insertedSections = insertedSections
		self.deletedSections = deletedSections
		self.reloadedSections = reloadedSections
	}
}

extension ReactiveSetEvent: CustomStringConvertible {
	public var description: String {
		switch self {
		case .reloaded:
			return "ReactiveSetEvent.Reloaded"

		case let .updated(changes):
			return "ReactiveSetEvent.Updated [BEGIN]\n\(changes)\n[END]"
		}
	}
}

extension ReactiveSetEvent: CustomDebugStringConvertible {
	public var debugDescription: String {
		return description
	}
}

extension ReactiveSetChanges: CustomStringConvertible {
	public var description: String {
		var strings = [String]()
		strings.append("ReactiveSetChanges")

		if let indexPaths = insertedRows {
			strings.append("> \(indexPaths.count) row(s) inserted\n")
		}

		if let indexPaths = deletedRows {
			strings.append( "> \(indexPaths.count) row(s) deleted\n")
		}

		if let indexPaths = movedRows {
			strings.append( "> \(indexPaths.count) row(s) moved\n")
		}

		if let indexPaths = updatedRows {
			strings.append( "> \(indexPaths.count) row(s) updated\n")
		}

		if let indexPaths = insertedSections {
			strings.append( "> \(indexPaths.count) section(s) inserted\n")
		}

		if let indexPaths = deletedSections {
			strings.append( "> \(indexPaths.count) section(s) deleted\n")
		}
		
		return strings.joinWithSeparator("\n")
	}
}

extension ReactiveSetChanges: CustomDebugStringConvertible {
	public var debugDescription: String {
		return description
	}
}