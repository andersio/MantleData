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
