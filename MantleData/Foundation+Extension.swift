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
