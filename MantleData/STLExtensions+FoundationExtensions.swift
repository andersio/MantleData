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

extension CollectionType where Generator.Element: ReactiveSetSection {
	internal func index(forName name: ReactiveSetSectionName) -> Index? {
		for i in indices {
			if self[i].name == name {
				return i
			}
		}
		return nil
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

public protocol SetType {
	associatedtype Element: Hashable
	init()
	mutating func insert(member: Element)
	func contains(member: Element) -> Bool
}

extension Set: SetType { }

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

extension MutableCollectionType where Index: RandomAccessIndexType, Generator.Element: Object {
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