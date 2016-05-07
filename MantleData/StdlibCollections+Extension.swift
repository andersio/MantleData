//
//  StdlibCollections+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import protocol ReactiveCocoa.OptionalType

public enum BinarySearchResult<Index> {
	case found(at: Index)
	case notFound(next: Index)
}

extension CollectionType where Generator.Element == NSSortDescriptor {
	public func compare<E: NSObject>(element: E, to anotherElement: E) -> NSComparisonResult {
		for descriptor in self {
			let order = descriptor.compareObject(element, toObject: anotherElement)

			if order != .OrderedSame {
				return order
			}
		}

		return .OrderedSame
	}
}

extension CollectionType where Generator.Element == NSManagedObjectID, Index == Int {
	func bidirectionalSearch(at center: Int, for element: NSManagedObjectID, using sortDescriptors: [NSSortDescriptor], with cachedValues: [NSManagedObjectID: [String: AnyObject]]) -> BinarySearchResult<Index> {
		var leftIndex = center - 1
		while leftIndex >= startIndex && sortDescriptors.compare(cachedValues[self[leftIndex]]!, to: cachedValues[element]!) == .OrderedSame {
			if self[leftIndex] == element {
				return .found(at: leftIndex)
			}
			leftIndex -= 1
		}

		var rightIndex = center + 1
		while rightIndex < endIndex && sortDescriptors.compare(cachedValues[self[rightIndex]]!, to: cachedValues[element]!) == .OrderedSame {
			if self[rightIndex] == element {
				return .found(at: rightIndex)
			}
			rightIndex += 1
		}

		return .notFound(next: leftIndex + 1)
	}

	public func index(of element: NSManagedObjectID, using sortDescriptors: [NSSortDescriptor], with cachedValues: [NSManagedObjectID: [String: AnyObject]]) -> Index? {
		if case let .found(index) = binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
			return index
		}

		return nil
	}

	public func binarySearch(of element: NSManagedObjectID, using sortDescriptors: [NSSortDescriptor], with cachedValues: [NSManagedObjectID: [String: AnyObject]]) -> BinarySearchResult<Index> {
		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			if self[mid] == element {
				return .found(at: mid)
			} else {
				switch sortDescriptors.compare(cachedValues[element]!, to: cachedValues[self[mid]]!) {
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
	public mutating func insert(element: NSManagedObjectID, using sortDescriptors: [NSSortDescriptor], with cachedValues: [NSManagedObjectID: [String: AnyObject]]) {
		switch binarySearch(of: element, using: sortDescriptors, with: cachedValues) {
		case .found:
			return

		case let .notFound(insertingIndex):
			insert(element, atIndex: insertingIndex)
		}
	}
}