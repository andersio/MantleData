//
//  StdlibCollections+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import protocol ReactiveCocoa.OptionalType

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

	func bidirectionalSearch(at center: Int, for element: Generator.Element, using sortDescriptors: [NSSortDescriptor]) -> BinarySearchResult<Index> {
		var leftIndex = center - 1
		while leftIndex >= startIndex && sortDescriptors.compare(self[leftIndex], to: element) == .OrderedSame {
			if self[leftIndex] == element {
				return .found(at: leftIndex)
			}
			leftIndex -= 1
		}

		var rightIndex = center + 1
		while rightIndex < endIndex && sortDescriptors.compare(self[rightIndex], to: element) == .OrderedSame {
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
				switch sortDescriptors.compare(element, to: self[mid]) {
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