//
//  Foundation+Extension.swift
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
	public convenience init<SectionIndex: ReactiveSetIndex, RowIndex: ReactiveSetIndex>(converting indexPath: ReactiveSetIndexPath<SectionIndex, RowIndex>) {
		self.init(forRow: Int(indexPath.row.toIntMax()), inSection: Int(indexPath.section.toIntMax()))
	}
}

extension NSMutableIndexSet {
	public convenience init<Index: ReactiveSetIndex>(converting indices: [Index]) {
		self.init()
		for index in indices {
			self.addIndex(Int(index.toIntMax()))
		}
	}
}