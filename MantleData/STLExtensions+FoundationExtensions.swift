//
//  STLExtensions+FoundationExtensions.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

/// MARK: MantleData specific additions

extension Range where Element: CocoaBridgeable, Element: ForwardIndexType, Element.Distance: CocoaBridgeable {
	public var cocoaValue: NSRange {
		return NSRange(location: Int(cocoaValue: startIndex.cocoaValue),
			length: Int(cocoaValue: startIndex.distanceTo(endIndex).cocoaValue))
	}
}

public enum BinarySearchResult<Index> {
	case found(at: Index)
	case notFound(next: Index)
}

extension CollectionType where Generator.Element == NSSortDescriptor {
	public func compare<E: AnyObject>(element: E, to anotherElement: E) -> NSComparisonResult {
		for descriptor in self {
			let order = descriptor.compareObject(element, toObject: anotherElement)

			if order != .OrderedSame {
				return order
			}
		}

		return .OrderedSame
	}
}

extension CollectionType where Generator.Element: NSManagedObject, Index == Int {
	public func index(of element: Generator.Element, using sortDescriptors: [NSSortDescriptor]) -> Index? {
		if case let .found(index) = binarySearch(of: element, using: sortDescriptors) {
			return index
		}

		return nil
	}

	public func binarySearch(of element: Generator.Element, using sortDescriptors: [NSSortDescriptor]) -> BinarySearchResult<Index> {
		func bidirectionalSearch(center index: Int, using sortDescriptors: [NSSortDescriptor]) -> BinarySearchResult<Index> {
			var leftIndex = index - 1
			while leftIndex >= startIndex && sortDescriptors.compare(self[leftIndex], to: element) == .OrderedSame {
				if self[leftIndex] == element {
					return .found(at: leftIndex)
				}
				leftIndex -= 1
			}

			var rightIndex = index + 1
			while rightIndex < endIndex && sortDescriptors.compare(self[rightIndex], to: element) == .OrderedSame {
				if self[rightIndex] == element {
					return .found(at: rightIndex)
				}
				rightIndex += 1
			}

			return .notFound(next: leftIndex + 1)
		}

		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			if self[mid] == element {
				return .found(at: mid)
			} else {
				switch sortDescriptors.compare(element, to: self[mid]) {
				case .OrderedAscending:
					high = mid - 1

				case .OrderedDescending:
					low = mid + 1

				case .OrderedSame:
					return bidirectionalSearch(center: mid, using: sortDescriptors)
				}
			}
		}

		return .notFound(next: high + 1)
	}

	public func index(of element: Generator.Element, using sortDescriptors: [NSSortDescriptor], with substitution: [Generator.Element: [String: AnyObject]]) -> Index? {
		if case let .found(index) = binarySearch(of: element, using: sortDescriptors, with: substitution) {
			return index
		}

		return nil
	}

	func compare(element: NSObject, to anotherElement: NSObject, using descriptors: [NSSortDescriptor]) -> NSComparisonResult {
		for descriptor in descriptors {
			let order = descriptor.compareObject(element, toObject: anotherElement)

			if order != .OrderedSame {
				return order
			}
		}

		return .OrderedSame
	}

	func bidirectionalSearch(at center: Int, for element: Generator.Element, using sortDescriptors: [NSSortDescriptor]) -> BinarySearchResult<Index> {
		var leftIndex = center - 1
		while leftIndex >= startIndex && compare(self[leftIndex], to: element, using: sortDescriptors) == .OrderedSame {
			if self[leftIndex] == element {
				return .found(at: leftIndex)
			}
			leftIndex -= 1
		}

		var rightIndex = center + 1
		while rightIndex < endIndex && compare(self[rightIndex], to: element, using: sortDescriptors) == .OrderedSame {
			if self[rightIndex] == element {
				return .found(at: rightIndex)
			}
			rightIndex += 1
		}

		return .notFound(next: leftIndex + 1)
	}

	public func binarySearch(of element: Generator.Element, using sortDescriptors: [NSSortDescriptor], with substitution: [Generator.Element: [String: AnyObject]]) -> BinarySearchResult<Index> {
		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			if self[mid] == element {
				return .found(at: mid)
			} else {
				switch compare(element, to: self[mid], using: sortDescriptors) {
				case .OrderedAscending:
					high = mid - 1

				case .OrderedDescending:
					low = mid + 1

				case .OrderedSame:
					return bidirectionalSearch(at: mid, for: element, using: sortDescriptors)
				}
			}
		}

		return .notFound(next: high + 1)
	}
}

extension RangeReplaceableCollectionType where Generator.Element: NSManagedObject, Index == Int {
	public mutating func insert(element: Generator.Element, using sortDescriptors: [NSSortDescriptor]) {
		switch binarySearch(of: element, using: sortDescriptors) {
		case .found:
			return

		case let .notFound(insertingIndex):
			insert(element, atIndex: insertingIndex)
		}
	}
}

extension RangeReplaceableCollectionType where Generator.Element: ReactiveSetSection {
	internal mutating func insert(section: Generator.Element, name: ReactiveSetSectionName, ordering: NSComparisonResult) -> Index {
		let position: Index
		if let searchResult = indexOf({ $0.name.compareTo(name) != ordering }) {
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

public protocol SetType {
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
	internal mutating func insert(value: Value.Element, intoSetOfKey key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.insert(value)
	}
}

extension Dictionary where Value: protocol<ArrayLiteralConvertible, RangeReplaceableCollectionType>, Value.Generator.Element == Value.Element {
	internal mutating func insert(value: Value.Element, intoSetOfKey key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.append(value)
	}
}

extension MutableCollectionType where Index: RandomAccessIndexType, Generator.Element: NSManagedObject {
	internal mutating func sort(with sortDescriptors: [NSSortDescriptor]) {
		if sortDescriptors.count == 0 {
			return
		}

		sortInPlace { object1, object2 in
			return sortDescriptors.contains { descriptor in
				return descriptor.compareObject(object1, toObject: object2) == .OrderedAscending
			}
		}
	}
}

extension CollectionType where Generator.Element: OptionalType, Generator.Element.Wrapped: NSIndexSet {
	public func flattened() -> NSIndexSet {
		let flattenedIndexSet = NSMutableIndexSet()
		forEach {
			if let indexSet = $0.optional {
				flattenedIndexSet.addIndexes(indexSet)
			}
		}
		return flattenedIndexSet
	}
}

extension CollectionType where Generator.Element == NSIndexPath {
	public func mapped(prependingIndex index: Int) -> [Generator.Element] {
		return map {
			NSIndexPath($0, prepending: index)
		}
	}
}

extension CollectionType where Generator.Element == (NSIndexPath, NSIndexPath) {
	public func mapped(prependingIndex index: Int) -> [Generator.Element] {
		return map {
			(NSIndexPath($0.0, prepending: index), NSIndexPath($0.1, prepending: index))
		}
	}
}

#if os(OSX)
	extension NSIndexPath {
		public convenience init(forRow row: Int, inSection section: Int) {
			self.init(forItem: row, inSection: section)
		}

		public convenience init(forSection section: Int) {
			self.init(index: section)
		}

		public var row: Int {
			return item
		}
	}
#endif

extension NSIndexPath {
	public convenience init(_ source: NSIndexPath, prepending newIndex: Int) {
		let length = source.length + 1
		let indexes = UnsafeMutablePointer<Int>.alloc(length)
		indexes[0] = newIndex

		let copyingPointer = indexes.advancedBy(1)
		source.getIndexes(copyingPointer)

		self.init(indexes: indexes, length: length)
		indexes.destroy()
		indexes.dealloc(length)
	}
}

extension Dictionary where Value: Equatable {
	public func difference(from otherDictionary: Dictionary<Key, Value>) -> Dictionary<Key, (this: Value?, other: Value?)> {
		let localKeys = Set(keys)
		let otherKeys = Set(otherDictionary.keys)
		let intersection = localKeys.intersect(otherKeys)
		let localUnique = Set(keys).subtract(intersection)
		let otherUnique = Set(otherDictionary.keys).subtract(intersection)

		var returnDictionary = [Key: (this: Value?, other: Value?)]()

		for key in intersection {
			if let localValue = self[key], otherValue = otherDictionary[key] where localValue != otherValue {
				returnDictionary[key] = (this: localValue, other: otherValue)
			}
		}

		for key in localUnique {
			if let value = self[key] {
				returnDictionary[key] = (this: value, other: nil)
			}
		}

		for key in otherUnique {
			if let value = otherDictionary[key] {
				returnDictionary[key] = (this: nil, other: value)
			}
		}

		return returnDictionary
	}
}