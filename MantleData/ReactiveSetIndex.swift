//
//  ReactiveSetIndex.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

public struct ReactiveSetIndexPath: Comparable {
	public let section: Int
	public let row: Int

	public init<L: ReactiveSetIndex, R: ReactiveSetIndex>(section: L, row: R) {
		self.section = section.toInt()
		self.row = row.toInt()
	}

	public init(section: Int, row: Int) {
		self.section = section
		self.row = row
	}
}

extension ReactiveSetIndexPath: _ObjectiveCBridgeable {
	public typealias _ObjectiveCType = NSIndexPath

	public static func _isBridgedToObjectiveC() -> Bool {
		return true
	}

	public static func _getObjectiveCType() -> Any.Type {
		return NSIndexPath.self
	}

	public func _bridgeToObjectiveC() -> _ObjectiveCType {
		return NSIndexPath(forRow: row, inSection: section)
	}

	public static func _conditionallyBridgeFromObjectiveC(source: _ObjectiveCType, inout result: ReactiveSetIndexPath?) -> Bool {
		if source.length != 2 {
			return false
		}

		result = ReactiveSetIndexPath(section: source.section, row: source.row)
		return true
	}

	public static func _forceBridgeFromObjectiveC(source: _ObjectiveCType, inout result: ReactiveSetIndexPath?) {
		_conditionallyBridgeFromObjectiveC(source, result: &result)
	}
}

public func ==
	(left: ReactiveSetIndexPath, right: ReactiveSetIndexPath) -> Bool {
	return left.section == right.section && left.row == right.row
}

public func >=
	(left: ReactiveSetIndexPath, right: ReactiveSetIndexPath) -> Bool {
	return left.section > right.section || (left.section == right.section && left.row >= right.row)
}

public func <
	(left: ReactiveSetIndexPath, right: ReactiveSetIndexPath) -> Bool {
	return left.section < right.section || (left.section == right.section && left.row < right.row)
}

/// Index of ReactiveSet

public protocol ReactiveSetIndex: RandomAccessIndexType {
	init<I: ReactiveSetIndex>(converting: I)
	func toInt() -> Int
}

extension Int: ReactiveSetIndex {
	public init<I: ReactiveSetIndex>(converting index: I) {
		self = Int(index.toInt())
	}

	public func toInt() -> Int {
		return self
	}
}