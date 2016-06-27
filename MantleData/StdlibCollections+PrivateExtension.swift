//
//  StdlibCollections+PrivateExtension.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

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
																		using sortDescriptors: [SortDescriptor],
																		with cachedValues: [NSManagedObjectID: [String: AnyObject]])
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
											using sortDescriptors: [SortDescriptor],
											with cachedValues: [NSManagedObjectID: [String: AnyObject]])
											-> Index? {
		if case let .found(index) = binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
			return index
		}

		return nil
	}

	internal func binarySearch(of element: NSManagedObjectID,
														using sortDescriptors: [SortDescriptor],
														with cachedValues: [NSManagedObjectID: [String: AnyObject]])
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
	                              using sortDescriptors: [SortDescriptor],
																with cachedValues: [NSManagedObjectID: [String: AnyObject]]) {
		switch binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
		case .found:
			return

		case let .notFound(insertingIndex):
			insert(element, at: insertingIndex)
		}
	}
}

extension RangeReplaceableCollection where Iterator.Element: ReactiveSetSection {
	internal mutating func insert(_ section: Iterator.Element,
	                              name: ReactiveSetSectionName,
	                              ordering: ComparisonResult) -> Index {
		let position: Index
		if let searchResult = self.index(where: { $0.name.compare(to: name) != ordering }) {
			position = searchResult
		} else {
			position = ordering == .orderedAscending ? startIndex : endIndex
		}

		insert(section, at: position)
		return position
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

extension MutableCollection where Iterator.Element: protocol<MutableCollection, RangeReplaceableCollection>, Iterator.Element.Iterator.Element: Comparable, Iterator.Element.Index == Int {
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

extension Dictionary where Value: protocol<ArrayLiteralConvertible, RangeReplaceableCollection>, Value.Iterator.Element == Value.Element {
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

extension Collection where Iterator.Element: ReactiveSetSection {
	public func index(of name: ReactiveSetSectionName) -> Index? {
		return index { $0.name == name }
	}
}
