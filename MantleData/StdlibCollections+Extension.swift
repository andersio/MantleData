//
//  StdlibCollections+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

extension Collection where Iterator.Element == SortDescriptor {
	public func compare<E: NSObject>(_ element: E, to anotherElement: E) -> ComparisonResult {
		for descriptor in self {
			let order = descriptor.compare(element, to: anotherElement)

			if order != .orderedSame {
				return order
			}
		}

		return .orderedSame
	}
}
