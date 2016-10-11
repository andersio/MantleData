//
//  Foundation+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

#if os(macOS)
	extension IndexPath {
		public init(row: Int, section: Int) {
			self.init(item: row, section: section)
		}

		public init(section: Int) {
			self.init(index: section)
		}

		public var row: Int {
			return item
		}
	}
#endif

extension IndexPath {
	static func < (left: IndexPath, right: IndexPath) -> Bool {
		assert(left.count == right.count)
		for index in left.indices {
			if left[index] < right[index] {
				return true
			}
		}
		return false
	}
}
