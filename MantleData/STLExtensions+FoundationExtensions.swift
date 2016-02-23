//
//  STLExtensions+FoundationExtensions.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

extension Range where Element: CocoaBridgeable, Element: ForwardIndexType, Element.Distance: CocoaBridgeable {
	public var cocoaValue: NSRange {
		return NSRange(location: Int(cocoaValue: startIndex.cocoaValue),
			length: Int(cocoaValue: startIndex.distanceTo(endIndex).cocoaValue))
	}
}

extension CollectionType where Generator.Element: ReactiveSetSection {
	internal func indexFor(name: ReactiveSetSectionName) -> Index? {
		for i in indices {
			if self[i].name == name {
				return i
			}
		}
		return nil
	}
}

extension RangeReplaceableCollectionType where Generator.Element: ReactiveSetSection {
	internal mutating func insertSection(name: ReactiveSetSectionName, ordering: NSComparisonResult, section: Generator.Element) -> Index {
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

public protocol SetType {
	typealias Element: Hashable
	init()
	mutating func insert(member: Element)
	func contains(member: Element) -> Bool
}

extension Set: SetType { }

extension Dictionary where Value: SetType {
	internal mutating func insert(value: Value.Element, inSetForKey key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.insert(value)
	}
}

extension Dictionary where Value: protocol<ArrayLiteralConvertible, RangeReplaceableCollectionType>, Value.Generator.Element == Value.Element {
	internal mutating func insert(value: Value.Element, inSetForKey key: Key) {
		if !keys.contains(key) {
			self[key] = Value()
		}
		self[key]?.append(value)
	}
}

extension MutableCollectionType where Index: RandomAccessIndexType, Generator.Element: Object {
	internal mutating func _sortInPlace(sortDescriptors: [NSSortDescriptor]) {
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
	public func flatten() -> NSIndexSet {
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
	var _toString: String {
		return map { "[s#\($0.section) c#\($0.row)]" }
			.joinWithSeparator(", ")
	}

	public func appendIndex(index: Int) -> [Generator.Element] {
		return map {
			NSIndexPath(appendingIndex: index, to: $0)
		}
	}
}

extension CollectionType where Generator.Element == (NSIndexPath, NSIndexPath) {
	var _toString: String {
		return map { tuple in
				let (to, from) = tuple
				return "[s#\(from.section) c#\(from.row) to s#\(to.section) c#\(to.row)]"
			}
			.joinWithSeparator(", ")
	}

	public func appendIndex(index: Int) -> [Generator.Element] {
		return map {
			(NSIndexPath(appendingIndex: index, to: $0.0),
				NSIndexPath(appendingIndex: index, to: $0.1))
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
	public convenience init(appendingIndex: Int, to: NSIndexPath) {
		let length = to.length + 1
		let indexes = UnsafeMutablePointer<Int>.alloc(length)
		indexes[0] = appendingIndex

		let copyingPointer = indexes.advancedBy(1)
		to.getIndexes(copyingPointer)

		self.init(indexes: indexes, length: length)
		indexes.destroy()
		indexes.dealloc(length)
	}
}

extension NSIndexSet {
	var _toString: String {
		return map { "s#\($0)" }
			.joinWithSeparator(", ")
	}
}