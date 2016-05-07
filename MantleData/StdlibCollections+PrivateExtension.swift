//
//  StdlibCollections+PrivateExtension.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

extension RangeReplaceableCollectionType where Generator.Element: ReactiveSetSection {
	internal mutating func insert(section: Generator.Element, name: ReactiveSetSectionName, ordering: NSComparisonResult) -> Index {
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

/// Generic additions:

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