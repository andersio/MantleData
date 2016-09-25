//
//  StdlibCollections+PrivateExtension.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveSwift

extension String {
	public static func compareSectionNames(_ first: String?, with second: String?) -> ComparisonResult {
		guard let unwrappedFirst = first, let unwrappedSecond = second else {
			return first == nil ? (first == second ? .orderedSame : .orderedAscending) : .orderedDescending
		}

		return unwrappedFirst.compare(unwrappedSecond)
	}
}

extension SignedInteger {
	internal init<I: SignedInteger>(unsafeCasting integer: I) {
		self.init(integer.toIntMax())
	}
}

internal enum BinarySearchResult<Index> {
	case found(at: Index)
	case notFound(next: Index)
}

extension Collection where Iterator.Element == NSManagedObjectID, Index == Int {
	internal func bidirectionalSearch(at center: Int,
																		for element: NSManagedObjectID,
																		using sortDescriptors: [NSSortDescriptor],
																		with cachedValues: [NSManagedObjectID: [String: NSObject]])
																		-> BinarySearchResult<Index> {
		var leftIndex = center - 1
		while leftIndex >= startIndex &&
					sortDescriptors.compare(cachedValues[self[leftIndex]]! as NSDictionary,
					                        to: cachedValues[element]! as NSDictionary)
					== .orderedSame {
			if self[leftIndex] == element {
				return .found(at: leftIndex)
			}
			leftIndex -= 1
		}

		var rightIndex = center + 1
		while rightIndex < endIndex &&
					sortDescriptors.compare(cachedValues[self[rightIndex]]! as NSDictionary,
					                        to: cachedValues[element]! as NSDictionary)
					== .orderedSame {
			if self[rightIndex] == element {
				return .found(at: rightIndex)
			}
			rightIndex += 1
		}

		return .notFound(next: leftIndex + 1)
	}

	internal func index(of element: NSManagedObjectID,
											using sortDescriptors: [NSSortDescriptor],
											with cachedValues: [NSManagedObjectID: [String: NSObject]])
											-> Index? {
		if case let .found(index) = binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
			return index
		}

		return nil
	}

	internal func binarySearch(of element: NSManagedObjectID,
														using sortDescriptors: [NSSortDescriptor],
														with cachedValues: [NSManagedObjectID: [String: NSObject]])
														-> BinarySearchResult<Index> {
		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			if self[mid] == element {
				return .found(at: mid)
			} else {
				switch sortDescriptors.compare(cachedValues[element]! as NSDictionary,
				                               to: cachedValues[self[mid]]! as NSDictionary) {
				case .orderedAscending:
					high = mid - 1

				case .orderedDescending:
					low = mid + 1

				case .orderedSame:
					return bidirectionalSearch(at: mid, for: element, using: sortDescriptors, with: cachedValues)
				}
			}
		}

		return .notFound(next: high + 1)
	}
}

extension RangeReplaceableCollection where Iterator.Element == NSManagedObjectID, Index == Int {
	internal mutating func insert(_ element: NSManagedObjectID,
	                              using sortDescriptors: [NSSortDescriptor],
																with cachedValues: [NSManagedObjectID: [String: NSObject]]) {
		switch binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
		case .found:
			return

		case let .notFound(insertingIndex):
			insert(element, at: insertingIndex)
		}
	}
}

extension Collection where Iterator.Element: Comparable, Index == Int {
	internal func binarySearch(_ element: Iterator.Element, ascending: Bool) -> BinarySearchResult<Index> {
		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			if self[mid] == element {
				return .found(at: mid)
			} else if (ascending ? self[mid] > element : self[mid] < element) {
				high = mid - 1
			} else {
				low = mid + 1
			}
		}

		return .notFound(next: high + 1)
	}
}

internal protocol SetProtocol {
	associatedtype Element: Hashable

	init()

	@discardableResult
	mutating func insert(_ member: Element) -> (inserted: Bool, memberAfterInsert: Element)

	func contains(_ member: Element) -> Bool
}

extension Set: SetProtocol {}

extension MutableCollection where Iterator.Element: MutableCollection & RangeReplaceableCollection, Iterator.Element.Iterator.Element: Comparable, Iterator.Element.Index == Int {
	internal mutating func orderedInsert(_ value: Iterator.Element.Iterator.Element, toCollectionAt index: Index, ascending: Bool = true) {
		if case let .notFound(insertionPoint) = self[index].binarySearch(value, ascending: ascending) {
			self[index].insert(value, at: insertionPoint)
		}
	}
}
extension Array where Element: SetProtocol {
	internal mutating func insert(_ value: Element.Element, intoSetAt index: Index) {
		self[index].insert(value)
	}
}

extension Dictionary where Value: SetProtocol {
	internal mutating func insert(_ value: Value.Element, intoSetOf key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.insert(value)
	}
}

extension Dictionary where Value: ExpressibleByArrayLiteral & RangeReplaceableCollection, Value.Iterator.Element == Value.Element {
	internal mutating func append(_ value: Value.Element, toCollectionOf key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.append(value)
	}
}

extension Collection where Iterator.Element: Hashable {
	internal func uniquing() -> [Iterator.Element] {
		return Array(Set(self))
	}
}
