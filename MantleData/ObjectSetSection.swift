//
//  ObjectSetSection.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

public struct ObjectSetSection<E: NSManagedObject> {
	public let name: ReactiveSetSectionName

	public internal(set) var indexInSet: Int
	internal var storage: ContiguousArray<NSManagedObjectID>
	private unowned var parentSet: ObjectSet<E>

	public init(at index: Int, name: ReactiveSetSectionName, array: ContiguousArray<NSManagedObjectID>?, in parentSet: ObjectSet<E>) {
		self.indexInSet = index
		self.name = name
		self.storage = array ?? []
		self.parentSet = parentSet
	}
}

extension ObjectSetSection: ReactiveSetSection {
	public typealias Iterator = AnyReactiveSetSectionIterator<E>
	public typealias Index = Int

	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public subscript(position: Int) -> E {
		get {
			parentSet.prefetcher?.acknowledgeNextAccess(at: IndexPath(row: position, section: indexInSet))
			
			if let object = parentSet.context.registeredObject(for: storage[position]) as? E {
				return object
			}

			return parentSet.context.object(with: storage[position]) as! E
		}
		set { storage[position] = newValue.objectID }
	}

	public func makeIterator() -> AnyReactiveSetSectionIterator<E> {
		var index = startIndex
		let limit = endIndex

		return AnyReactiveSetSectionIterator {
			defer { index = (index + 1) }
			return index < limit ? self[index] : nil
		}
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}
}

extension ObjectSetSection: RangeReplaceableCollection {
	public init() {
		_unimplementedMethod()
	}

	public mutating func replaceSubrange<C : Collection where C.Iterator.Element == E>(_ subRange: Range<Int>, with newElements: C) {
		storage.replaceSubrange(subRange, with: newElements.map { $0.objectID })
	}
}

extension ObjectSetSection: MutableCollection {}
