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
	public typealias Generator = AnyReactiveSetSectionIterator<E>
	public typealias Index = Int

	public var startIndex: Int {
		return storage.startIndex
	}

	public var endIndex: Int {
		return storage.endIndex
	}

	public subscript(position: Int) -> E {
		get {
			parentSet.prefetcher?.acknowledgeNextAccess(at: ReactiveSetIndexPath(section: indexInSet, row: position))
			
			if let object = parentSet.context.objectRegisteredForID(storage[position]) as? E {
				return object
			}

			return parentSet.context.objectWithID(storage[position]) as! E
		}
		set { storage[position] = newValue.objectID }
	}

	public func generate() -> AnyReactiveSetSectionIterator<E> {
		var index = startIndex
		let limit = endIndex

		return AnyReactiveSetSectionIterator {
			defer { index = index.successor() }
			return index < limit ? self[index] : nil
		}
	}
}

extension ObjectSetSection: RangeReplaceableCollectionType {
	public init() {
		_unimplementedMethod()
	}

	public mutating func replaceRange<C : CollectionType where C.Generator.Element == E>(subRange: Range<Int>, with newElements: C) {
		storage.replaceRange(subRange, with: newElements.map { $0.objectID })
	}
}

extension ObjectSetSection: MutableCollectionType {}