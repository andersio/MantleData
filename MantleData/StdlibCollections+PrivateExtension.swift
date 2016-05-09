//
//  StdlibCollections+PrivateExtension.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

internal enum BinarySearchResult<Index> {
	case found(at: Index)
	case notFound(next: Index)
}

extension CollectionType where Generator.Element == NSManagedObjectID, Index == Int {
	internal func bidirectionalSearch(at center: Int,
																		for element: NSManagedObjectID,
																		using sortDescriptors: [NSSortDescriptor],
																		with cachedValues: [NSManagedObjectID: [String: AnyObject]])
																		-> BinarySearchResult<Index> {
		var leftIndex = center - 1
		while leftIndex >= startIndex &&
					sortDescriptors.compare(cachedValues[self[leftIndex]]! as NSDictionary,
					                        to: cachedValues[element]! as NSDictionary)
					== .OrderedSame {
			if self[leftIndex] == element {
				return .found(at: leftIndex)
			}
			leftIndex -= 1
		}

		var rightIndex = center + 1
		while rightIndex < endIndex &&
					sortDescriptors.compare(cachedValues[self[rightIndex]]! as NSDictionary,
					                        to: cachedValues[element]! as NSDictionary)
					== .OrderedSame {
			if self[rightIndex] == element {
				return .found(at: rightIndex)
			}
			rightIndex += 1
		}

		return .notFound(next: leftIndex + 1)
	}

	internal func index(of element: NSManagedObjectID,
											using sortDescriptors: [NSSortDescriptor],
											with cachedValues: [NSManagedObjectID: [String: AnyObject]])
											-> Index? {
		if case let .found(index) = binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
			return index
		}

		return nil
	}

	internal func binarySearch(of element: NSManagedObjectID,
														using sortDescriptors: [NSSortDescriptor],
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
				case .OrderedAscending:
					high = mid - 1

				case .OrderedDescending:
					low = mid + 1

				case .OrderedSame:
					return bidirectionalSearch(at: mid, for: element, using: sortDescriptors, with: cachedValues)
				}
			}
		}

		return .notFound(next: high + 1)
	}
}

extension RangeReplaceableCollectionType where Generator.Element == NSManagedObjectID, Index == Int {
	internal mutating func insert(element: NSManagedObjectID,
	                              using sortDescriptors: [NSSortDescriptor],
																with cachedValues: [NSManagedObjectID: [String: AnyObject]]) {
		switch binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
		case .found:
			return

		case let .notFound(insertingIndex):
			insert(element, atIndex: insertingIndex)
		}
	}
}

extension RangeReplaceableCollectionType where Generator.Element: ReactiveSetSection {
	internal mutating func insert(section: Generator.Element,
	                              name: ReactiveSetSectionName,
	                              ordering: NSComparisonResult) -> Index {
		let position: Index
		if let searchResult = indexOf({ $0.name.compare(to: name) != ordering }) {
			position = searchResult
		} else {
			position = ordering == .OrderedAscending ? startIndex : endIndex
		}

		insert(section, atIndex: position)
		return position
	}
}

extension CollectionType where Generator.Element: Comparable, Index == Int {
	internal func binarySearch(element: Generator.Element, ascending: Bool) -> BinarySearchResult<Index> {
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

internal protocol SetType {
	associatedtype Element: Hashable
	init()
	mutating func insert(member: Element)
	func contains(member: Element) -> Bool
}

extension Set: SetType { }

extension MutableCollectionType where Generator.Element: protocol<MutableCollectionType, RangeReplaceableCollectionType>, Generator.Element.Generator.Element: Comparable, Generator.Element.Index == Int {
	internal mutating func orderedInsert(value: Generator.Element.Generator.Element, toCollectionAt index: Index, ascending: Bool = true) {
		if case let .notFound(insertionPoint) = self[index].binarySearch(value, ascending: ascending) {
			self[index].insert(value, atIndex: insertionPoint)
		}
	}
}
extension Array where Element: SetType {
	internal mutating func insert(value: Element.Element, intoSetAt index: Index) {
		self[index].insert(value)
	}
}

extension Dictionary where Value: SetType {
	internal mutating func insert(value: Value.Element, intoSetOf key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.insert(value)
	}
}

extension Dictionary where Value: protocol<ArrayLiteralConvertible, RangeReplaceableCollectionType>, Value.Generator.Element == Value.Element {
	internal mutating func append(value: Value.Element, toCollectionOf key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.append(value)
	}
}

extension CollectionType where Generator.Element: Hashable {
	internal func uniquing() -> [Generator.Element] {
		return Array(Set(self))
	}
}