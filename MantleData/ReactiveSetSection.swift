//
//  ReactiveSetSection.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

/// Section of ReactiveSet

public protocol ReactiveSetSectionGenerator: GeneratorType {
	associatedtype Element: Equatable
}

public protocol ReactiveSetSection: CollectionType {
	associatedtype Generator: ReactiveSetSectionGenerator
	associatedtype Index: ReactiveSetIndex

	var name: ReactiveSetSectionName { get }
}

public func == <S: ReactiveSetSection>(left: S, right: S) -> Bool {
	return left.name == right.name
}

public struct AnyReactiveSetSectionIterator<E: Equatable>: ReactiveSetSectionGenerator {
	public typealias Element = E

	private let generator: () -> Element?

	public init(generator: () -> Element?) {
		self.generator = generator
	}

	public mutating func next() -> Element? {
		return generator()
	}
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
	public func compareTo(otherName: ReactiveSetSectionName) -> NSComparisonResult {
		if let value = value, otherValue = otherName.value {
			return value.compare(otherValue)
		}

		if value == nil {
			// (nil) compare to (otherName)
			return .OrderedAscending
		}

		if otherName.value == nil {
			// (self) compare to (nil)
			return .OrderedDescending
		}

		// (nil) compare to (nil)
		return .OrderedSame
	}
}

public func ==(lhs: ReactiveSetSectionName, rhs: ReactiveSetSectionName) -> Bool {
	return lhs.value == rhs.value
}