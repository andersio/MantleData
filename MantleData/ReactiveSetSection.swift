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
	associatedtype Element
}

public protocol ReactiveSetSection: CollectionType {
	associatedtype Generator: ReactiveSetSectionGenerator
	associatedtype Index: ReactiveSetIndex

	var name: ReactiveSetSectionName { get }
}

extension ReactiveSetSection {
	public subscript(index: Int) -> Generator.Element {
		return self[Index(converting: index)]
	}
}

public func == <S: ReactiveSetSection>(left: S, right: S) -> Bool {
	return left.name == right.name
}

public struct AnyReactiveSetSectionIterator<E>: ReactiveSetSectionGenerator {
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
	public func compare(to anotherName: ReactiveSetSectionName) -> NSComparisonResult {
		if let value = value, anotherValue = anotherName.value {
			return value.compare(anotherValue)
		}

		if value == nil {
			// (nil) compare to (otherName)
			return .OrderedAscending
		}

		if anotherName.value == nil {
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