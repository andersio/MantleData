//
//  ReactiveCocoa+Additions.swift
//  MantleData
//
//  Created by Anders on 24/4/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

extension PropertyType {
	public func map<T>(transform: Value -> T) -> AnyProperty<T> {
		return AnyProperty<T>(initialValue: transform(value),
		                   producer: producer.map(transform))
	}
}
