//
//  ReactiveSetSection.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

/// Section of ReactiveSet

public protocol ReactiveSetSection: BidirectionalCollection {
	associatedtype Index: SignedInteger

	static var uniformDistance: IndexDistance { get }

	var name: ReactiveSetSectionName { get }
}

extension ReactiveSetSection {
	public static var uniformDistance: IndexDistance {
		return 1
	}
}

public func == <S: ReactiveSetSection>(left: S, right: S) -> Bool {
	return left.name == right.name
}

/// Section Name of ReactiveSet

public struct ReactiveSetSectionName: Hashable {
	public let value: String?

	public init() {
		self.value = nil
	}

	public init(exact string: String) {
		self.value = string
	}

	public init(converting object: AnyObject?) {
		switch object {
		case let name as String:
			self = ReactiveSetSectionName(exact: name)
		case let name as NSNumber:
			self = ReactiveSetSectionName(exact: name.stringValue)
		case is NSNull:
			self = ReactiveSetSectionName()
		default:
			assertionFailure("Expected NSNumber or NSString for ReactiveSetSectionName.")
			self = ReactiveSetSectionName()
		}
	}

	public var hashValue: Int {
		return value?.hashValue ?? 0
	}

	/// `nil` is defined as the smallest of all.
	public func compare(to anotherName: ReactiveSetSectionName) -> ComparisonResult {
		if let value = value, anotherValue = anotherName.value {
			return value.compare(anotherValue)
		}

		if value == nil {
			// (nil) compare to (otherName)
			return .orderedAscending
		}

		if anotherName.value == nil {
			// (self) compare to (nil)
			return .orderedDescending
		}

		// (nil) compare to (nil)
		return .orderedSame
	}
}

public func ==(lhs: ReactiveSetSectionName, rhs: ReactiveSetSectionName) -> Bool {
	return lhs.value == rhs.value
}
