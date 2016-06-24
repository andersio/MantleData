//
//  ObjectSetSection.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

public struct ObjectSetSection<E: NSManagedObject>: ReactiveSetSection {
	public typealias Index = Int
	public typealias Iterator = AnyIterator<E>

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

	public subscript(subRange: Range<Int>) -> BidirectionalSlice<ObjectSetSection<E>> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func makeIterator() -> AnyIterator<E> {
		var index: Index? = startIndex
		return AnyIterator {
			return index.map { currentIndex in
				defer { index = self.index(currentIndex, offsetBy: 1, limitedBy: self.endIndex) }
				return self[currentIndex]
			}
		}
	}

	public func index(after i: Index) -> Index {
		return i + 1
	}

	public func index(before i: Index) -> Index {
		return i - 1
	}
}
