//
//  UIKit+Bindings.swift
//  MantleData
//
//  Created by Anders on 10/3/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import UIKit
import ReactiveCocoa

infix operator <| { precedence 93 }

public func <| <Input>(left: (SignalProducer<Input?, NoError>) -> Void, right: SignalProducer<Input, NoError>) {
	left(right.map { $0 })
}

public func <| <Input>(left: (SignalProducer<Input, NoError>) -> Void, right: SignalProducer<Input, NoError>) {
	left(right)
}

public func <| <Input, Property: PropertyProtocol where Property.Value == Input>(left: (SignalProducer<Input, NoError>) -> Void, right: Property) {
	left <| right.producer
}

extension UIView {
	public var rxBackgroundColor: (SignalProducer<UIColor?, NoError>) -> Void {
		return { producer in
			producer
				.take(until: self.willDeinitProducer)
				.startWithNext { [unowned self] color in
					self.backgroundColor = color
				}
		}
	}
}

extension UILabel {
	public var rxText: (SignalProducer<String?, NoError>) -> Void {
		return { producer in
			producer
				.take(until: self.willDeinitProducer)
				.startWithNext { [unowned self] text in
					self.text = text
				}
		}
	}
}
