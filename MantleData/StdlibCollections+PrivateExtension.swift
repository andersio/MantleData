//
//  StdlibCollections+PrivateExtension.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import ReactiveSwift

extension SignedInteger {
	internal init<I: SignedInteger>(unsafeCasting integer: I) {
		self.init(integer.toIntMax())
	}
}

internal enum BinarySearchResult<Index> {
	case found(at: Index)
	case notFound(next: Index)
}

extension Collection where Iterator.Element: ObjectReferenceProtocol, Index == Int {
	internal func bidirectionalSearch(at center: Int, for element: Iterator.Element, with comparer: Comparer<Iterator.Element.Object>) -> BinarySearchResult<Index> {
		var leftIndex = center - 1
		while leftIndex >= startIndex && comparer.compare(self[leftIndex], to: element) == .orderedSame {
			if self[leftIndex] == element {
				return .found(at: leftIndex)
			}
			leftIndex -= 1
		}

		var rightIndex = center + 1
		while rightIndex < endIndex && comparer.compare(self[rightIndex], to: element) == .orderedSame {
			if self[rightIndex] == element {
				return .found(at: rightIndex)
			}
			rightIndex += 1
		}

		return .notFound(next: leftIndex + 1)
	}

	internal func index(of element: Iterator.Element, with comparer: Comparer<Iterator.Element.Object>) -> Index? {
		if case let .found(index) = binarySearch(of: element, with: comparer) {
			return index
		}

		return nil
	}

	internal func binarySearch(of element: Iterator.Element, with comparer: Comparer<Iterator.Element.Object>) -> BinarySearchResult<Index> {
		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			if self[mid] == element {
				return .found(at: mid)
			} else {
				switch comparer.compare(element, to: self[mid]) {
				case .orderedAscending:
					high = mid - 1

				case .orderedDescending:
					low = mid + 1

				case .orderedSame:
					return bidirectionalSearch(at: mid, for: element, with: comparer)
				}
			}
		}

		return .notFound(next: high + 1)
	}
}

extension RangeReplaceableCollection where Iterator.Element: ObjectReferenceProtocol, Index == Int {
	internal mutating func insert(_ element: Iterator.Element, with comparer: Comparer<Iterator.Element.Object>) {
		switch binarySearch(of: element, with: comparer) {
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

extension String {
	internal static func compareSectionNames(_ first: String?, with second: String?) -> ComparisonResult {
		guard let unwrappedFirst = first, let unwrappedSecond = second else {
			return first == nil ? (first == second ? .orderedSame : .orderedAscending) : .orderedDescending
		}

		return unwrappedFirst.compare(unwrappedSecond)
	}
}

extension Collection where Iterator.Element: SectionNameProviding, Index == Int {
	fileprivate func binarySearch(name: String?, ascending: Bool) -> BinarySearchResult<Int> {
		var low = startIndex
		var high = endIndex - 1

		while low <= high {
			let mid = (high + low) / 2

			switch String.compareSectionNames(self[mid].name, with: name) {
			case .orderedSame:
				return .found(at: mid)

			case .orderedAscending:
				if ascending {
					low = mid + 1
				} else {
					high = mid - 1
				}

			case .orderedDescending:
				if ascending {
					high = mid - 1
				} else {
					low = mid + 1
				}
			}
		}

		return .notFound(next: high + 1)
	}

	internal func index(of name: String?, ascending: Bool) -> Int? {
		switch binarySearch(name: name, ascending: ascending) {
		case let .found(position):
			return position
		case .notFound:
			return nil
		}
	}
}

extension RangeReplaceableCollection where Iterator.Element: SectionNameProviding, Index == Int {
	internal mutating func insert(_ section: Iterator.Element, name: String?, ascending: Bool) -> Index {
		if case let .notFound(next) = binarySearch(name: name, ascending: ascending) {
			insert(section, at: next)
			return next
		}

		preconditionFailure("Cannot insert sections with existing name.")
	}
}

extension MutableCollection where Iterator.Element: BoxProtocol, Iterator.Element.Value: MutableCollection & RangeReplaceableCollection, Iterator.Element.Value.Iterator.Element: Comparable, Iterator.Element.Value.Index == Int {
	internal mutating func orderedInsert(_ value: Iterator.Element.Value.Iterator.Element, toCollectionAt index: Index, ascending: Bool = true) {
		let box = self[index]
		if case let .notFound(insertionPoint) = box.value.binarySearch(value, ascending: ascending) {
			box.value.insert(value, at: insertionPoint)
		}
	}
}

extension Array where Element: BoxProtocol, Element.Value: SetAlgebra {
	internal mutating func insert(_ value: Element.Value.Element, intoSetAt index: Index) {
		self[index].value.insert(value)
	}
}

extension Dictionary where Value: BoxProtocol, Value.Value: SetAlgebra {
	internal mutating func insert(_ value: Value.Value.Element, intoSetOf key: Key) {
		var box = self[key]
		if box == nil {
			box = Value(Value.Value())
			self[key] = box!
		}

		box!.value.insert(value)
	}
}

extension Collection where Iterator.Element: Hashable {
	internal func uniquing() -> [Iterator.Element] {
		return Array(Set(self))
	}
}

protocol BoxProtocol: class {
	associatedtype Value

	var value: Value { get set }

	init(_ value: Value)
}

internal final class Box<Value>: BoxProtocol {
	var value: Value

	init(_ value: Value) {
		self.value = value
	}
}
