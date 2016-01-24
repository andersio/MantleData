//
//  NSObject+AssociatedProperty.swift
//  MantleData
//
//  Created by Anders on 22/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation

private var NSObjectExtAssociatedDictionaryKey = 0

extension NSObject {
	private var associatedDict: NSMutableDictionary {
		if let obj = objc_getAssociatedObject(self, &NSObjectExtAssociatedDictionaryKey) {
			return obj as! NSMutableDictionary
		}

		let dict = NSMutableDictionary()
		objc_setAssociatedObject(self, &NSObjectExtAssociatedDictionaryKey, dict, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		return dict
	}

	public func _associatedObjectFor(key: String) -> AnyObject? {
		let object = associatedDict.objectForKey(key)
		return object is NSNull ? nil : object
	}

	public func _setAssociatedObject(object: AnyObject?, key: String) {
		associatedDict.setObject(object ?? NSNull(), forKey: key)
	}
}