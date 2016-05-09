//
//  StdlibCollections+Extension.swift
//  MantleData
//
//  Created by Anders on 6/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import protocol ReactiveCocoa.OptionalType

extension CollectionType where Generator.Element == NSSortDescriptor {
	public func compare<E: NSObject>(element: E, to anotherElement: E) -> NSComparisonResult {
		for descriptor in self {
			let order = descriptor.compareObject(element, toObject: anotherElement)

			if order != .OrderedSame {
				return order
			}
		}

		return .OrderedSame
	}
}