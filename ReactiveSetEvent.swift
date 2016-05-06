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
	case Reloaded
	case Updated(Changes)
}

extension ReactiveSetEvent: CustomStringConvertible {
	public var description: String {
		switch self {
		case .Reloaded:
			return "ReactiveSetEvent.Reloaded"

		case let .Updated(changes):
			return "ReactiveSetEvent.Updated [BEGIN]\n\(changes)\n[END]"
		}
	}
}

/// Change Descriptor of ReactiveSet

extension ReactiveSetEvent {
	public struct Changes {
		public let indexPathsOfDeletedRows: [NSIndexPath]?
		public let indexPathsOfInsertedRows: [NSIndexPath]?
		public let indexPathsOfMovedRows: [(NSIndexPath, NSIndexPath)]?
		public let indexPathsOfUpdatedRows: [NSIndexPath]?

		public let indiceOfInsertedSections: NSIndexSet?
		public let indiceOfDeletedSections: NSIndexSet?
		public let indiceOfReloadedSections: NSIndexSet?

		public init(indexPathsOfDeletedRows: [NSIndexPath]? = nil, indexPathsOfInsertedRows: [NSIndexPath]? = nil, indexPathsOfMovedRows: [(NSIndexPath, NSIndexPath)]? = nil, indexPathsOfUpdatedRows: [NSIndexPath]? = nil, indiceOfInsertedSections: NSIndexSet? = nil, indiceOfDeletedSections: NSIndexSet? = nil, indiceOfReloadedSections: NSIndexSet? = nil) {
			func makeImmutable(indexSet: NSIndexSet?) -> NSIndexSet? {
				if let indexSet = indexSet {
					return indexSet is NSMutableIndexSet ? NSIndexSet(indexSet: indexSet) : indexSet
				} else {
					return nil
				}
			}

			self.indexPathsOfInsertedRows = indexPathsOfInsertedRows
			self.indexPathsOfDeletedRows = indexPathsOfDeletedRows
			self.indexPathsOfMovedRows = indexPathsOfMovedRows
			self.indexPathsOfUpdatedRows = indexPathsOfUpdatedRows
			self.indiceOfDeletedSections = makeImmutable(indiceOfDeletedSections)
			self.indiceOfInsertedSections = makeImmutable(indiceOfInsertedSections)
			self.indiceOfReloadedSections = makeImmutable(indiceOfReloadedSections)
		}

		public init(appendingIndex index: Int, changes: Changes) {
			self.init(indexPathsOfDeletedRows: changes.indexPathsOfDeletedRows?.mapped(prependingIndex: index),
			          indexPathsOfInsertedRows: changes.indexPathsOfInsertedRows?.mapped(prependingIndex: index),
			          indexPathsOfMovedRows: changes.indexPathsOfMovedRows?.mapped(prependingIndex: index),
			          indexPathsOfUpdatedRows: changes.indexPathsOfUpdatedRows?.mapped(prependingIndex: index))
		}
	}
}

extension ReactiveSetEvent.Changes: CustomStringConvertible {
	public var description: String {
		var strings = [String]()
		strings.append("ReactiveSetChanges")

		if let indexPaths = indexPathsOfInsertedRows {
			strings.append("> \(indexPaths.count) row(s) inserted\n")
		}

		if let indexPaths = indexPathsOfDeletedRows {
			strings.append( "> \(indexPaths.count) row(s) deleted\n")
		}

		if let indexPaths = indexPathsOfMovedRows {
			strings.append( "> \(indexPaths.count) row(s) moved\n")
		}

		if let indexPaths = indexPathsOfUpdatedRows {
			strings.append( "> \(indexPaths.count) row(s) updated\n")
		}

		if let indexPaths = indiceOfInsertedSections {
			strings.append( "> \(indexPaths.count) section(s) inserted\n")
		}

		if let indexPaths = indiceOfDeletedSections {
			strings.append( "> \(indexPaths.count) section(s) deleted\n")
		}
		
		return strings.joinWithSeparator("\n")
	}
}