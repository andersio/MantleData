//
//  UIKit+Editable.swift
//  MantleData
//
//  Created by Anders on 11/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import UIKit

extension UISwitch: Editable {
	public typealias Value = Bool

	public var value: Value {
		get { return isOn }
		set { isOn = newValue }
	}

	public func subscribeToChanges<SourceValue, TargetValue>(with editor: Editor<SourceValue, TargetValue>) {
		addTarget(editor,
		          action: #selector(Editor<SourceValue, TargetValue>.receive(_:forEvent:)),
		          for: .valueChanged)
	}

	public func unsubscribeToChanges<SourceValue, TargetValue>(with editor: Editor<SourceValue, TargetValue>) {
		removeTarget(editor,
		             action: #selector(Editor<SourceValue, TargetValue>.receive(_:forEvent:)),
		             for: .valueChanged)
	}
}
