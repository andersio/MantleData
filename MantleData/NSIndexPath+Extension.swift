//
//  NSIndexPath+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

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