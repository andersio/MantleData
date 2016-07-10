//
//  EditorPool.swift
//  MantleData
//
//  Created by Anders on 11/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// `EditorPool` concentrates a group of `Editor`s and allow batch commit and reset.
/// You may also supply a context to its initializer, so that it would auto-commit
/// at the time the context is being saved.
///
/// - Warning: Since the `Editor` is not thread-safe, this class inherits the caveat.
public class EditorPool: Base {
	private var editors: [EditorPoolToken: _EditorProtocol]
	private weak var context: NSManagedObjectContext?

	public init(autoCommitIn context: NSManagedObjectContext? = nil) {
		editors = [:]
		super.init()

		if let context = context {
			self.context = context

			NotificationCenter.default
				.rac_notifications(forName: .NSManagedObjectContextWillSave, object: context)
				.take(until: willDeinitProducer.zip(with: context.willDeinitProducer).map { _ in })
				.startWithNext(commit)
		}
	}

	public func add<SourceValue, TargetValue>(_ member: Editor<SourceValue, TargetValue>) -> EditorPoolToken {
		let token = EditorPoolToken()

		editors[token] = member
		return token
	}

	public func remove(_ token: EditorPoolToken) {
		editors.removeValue(forKey: token)
	}

	public func reset() {
		for editor in editors.values {
			editor.reset()
		}
	}

	@objc public func commit(_ notification: Notification) {
		for editor in editors.values {
			editor.commit()
		}
	}
}

public class EditorPoolToken: Hashable {
	public var hashValue: Int {
		return ObjectIdentifier(self).hashValue
	}
}

public func ==(left: EditorPoolToken, right: EditorPoolToken) -> Bool {
	return left === right
}
