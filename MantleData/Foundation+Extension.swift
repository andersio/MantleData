//
//  Foundation+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

#if os(OSX)
	extension IndexPath {
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
