//
//  Editor.swift
//  MantleData
//
//  Created by Anders on 1/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// `Editor` takes any `MutablePropertyProtocol` conforming types as its source, and
/// exposes a two-way binding interface for UIControl.
///
/// `Editor` would maintain a cached copy of the value. shall any conflict or
/// modification has been occured, this cached copy would be the latest version.
/// Therefore, you must explicitly commit the `Editor` at the time you need the
/// latest value.
///
/// - Warning: Since the `UIControl` subclasses are not thread-safe, this class
///            inherits the caveat.
public class Editor<SourceValue: Equatable, TargetValue: Equatable> {
	private let resetSignal: Signal<(), NoError>
	private let resetObserver: Signal<(), NoError>.Observer

	private let transform: EditorTransform<SourceValue, TargetValue>

	private let source: AnyMutableProperty<SourceValue>

	private weak var target: _Editable!
	private var targetGetter: (() -> TargetValue)!
	private var targetSetter: ((TargetValue) -> Void)!

	private let _cache: MutableProperty<SourceValue>
	public var cache: Property<SourceValue> {
		return Property(_cache)
	}

	private let mergePolicy: EditorMergePolicy<SourceValue, TargetValue>

	private var hasUserInitiatedChanges = false
	private var observerDisposable: CompositeDisposable

	public required init<Property: MutablePropertyProtocol where Property.Value == SourceValue>(source property: Property, mergePolicy: EditorMergePolicy<SourceValue, TargetValue>, transform: EditorTransform<SourceValue, TargetValue>) {
		self.source = AnyMutableProperty(property)
		self.mergePolicy = mergePolicy
		self.transform = transform

		observerDisposable = CompositeDisposable()
		(resetSignal, resetObserver) = Signal<(), NoError>.pipe()

		/// Thread safety is not a concern.
		_cache = MutableProperty(property.value)
		observerDisposable += property.signal.observeNext { value in
			self._cache.value = value
		}
	}

	public func bindTo<E: Editable where E.Value == TargetValue>(_ control: E, until: SignalProducer<(), NoError>) {
		assert(target == nil)

		until.startWithCompleted { [weak self] in
			self?.cleanUp()
		}

		target = control
		target.subscribeToChanges(with: self)

		targetGetter = { [unowned control] in control.value }
		targetSetter = { [unowned control] in control.value = $0 }

		observerDisposable += source.producer
			.startWithNext { [unowned self] value in
				self.targetSetter(self.transform.sourceToTarget(value))
			}
	}

	public func bindTo<E: Editable where E.Value == TargetValue>(_ target: E, until: Signal<(), NoError>) {
		bindTo(target, until: SignalProducer(signal: until))
	}

	public func reset() {
		hasUserInitiatedChanges = false
		observerDisposable.dispose()
		observerDisposable = CompositeDisposable()
		resetObserver.sendNext(())

		_cache.value = source.value
		observerDisposable += source.producer
			.startWithNext { [unowned self] value in
				self.targetSetter(self.transform.sourceToTarget(value))
			}
	}

	public func commit() {
		if source.value != _cache.value {
			source.value = _cache.value
		}
	}

	@objc public func receive(_ sender: UIControl, forEvent: UIControlEvents) {
		let targetValue = transform.targetToSource(targetGetter())

		if _cache.value == targetValue {
			return
		}

		if !hasUserInitiatedChanges {
			hasUserInitiatedChanges = true

			observerDisposable.dispose()
			_cache.value = targetValue

			source.signal
				.takeUntil(resetSignal)
				.observeNext { [unowned self] newSourceValue in
					/// conflict
					let currenttargetValue = self.transform.targetToSource(self.targetGetter())
					if newSourceValue != currenttargetValue {
						switch self.mergePolicy {
						case .overwrite:
							self._cache.value = currenttargetValue

						case let .notify(handler):
							let newValue = handler(sourceVersion: newSourceValue, targetVersion: currenttargetValue)
								self.targetSetter(self.transform.sourceToTarget(newValue))
								self._cache.value = newValue
						}
					}
				}
		} else {
			_cache.value = targetValue
		}
	}

	private func cleanUp() {
		observerDisposable.dispose()
		target?.unsubscribeToChanges(with: self)
		resetObserver.sendCompleted()
	}

	deinit {
		cleanUp()
	}
}

public protocol EditorProtocol {
	associatedtype _SourceValue: Equatable
	associatedtype _TargetValue: Equatable
	init<Property: MutablePropertyProtocol where Property.Value == _SourceValue>(source property: Property, mergePolicy: EditorMergePolicy<_SourceValue, _TargetValue>, transform: EditorTransform<_SourceValue, _TargetValue>)
}

extension EditorProtocol where _SourceValue == _TargetValue {
	public init<Property: MutablePropertyProtocol where Property.Value == _SourceValue>(source property: Property, mergePolicy: EditorMergePolicy<_SourceValue, _TargetValue>) {
		self.init(source: property, mergePolicy: mergePolicy, transform: EditorTransform())
	}
}

extension Editor: EditorProtocol, _EditorProtocol {
	public typealias _SourceValue = SourceValue
	public typealias _TargetValue = TargetValue
}

public struct EditorTransform<SourceValue: Equatable, TargetValue: Equatable> {
	public let sourceToTarget: (SourceValue) -> TargetValue
	public let targetToSource: (TargetValue) -> SourceValue

	public init(sourceToTarget forwardAction: (SourceValue) -> TargetValue, targetToSource backwardAction: (TargetValue) -> SourceValue) {
		sourceToTarget = forwardAction
		targetToSource = backwardAction
	}
}

public protocol EditorTransformProtocol {
	associatedtype _SourceValue: Equatable
	associatedtype _TargetValue: Equatable
	init(sourceToTarget forwardAction: (_SourceValue) -> _TargetValue, targetToSource backwardAction: (_TargetValue) -> _SourceValue)
}
extension EditorTransform: EditorTransformProtocol {
	public typealias _SourceValue = SourceValue
	public typealias _TargetValue = TargetValue
}

extension EditorTransformProtocol where _SourceValue == _TargetValue {
	public init() {
		self.init(sourceToTarget: { $0 }, targetToSource: { $0 })
	}
}

/// `EditorMergePolicy` specifies how an `Editor` should handle a conflict between
/// the source property and the target UI control.
public enum EditorMergePolicy<SourceValue: Equatable, TargetValue: Equatable> {
	/// Overwrite the source.
	case overwrite

	/// Overwrite both the source and target with the returned value of
	/// the custom handler.
	case notify(handler: (sourceVersion: SourceValue, targetVersion: SourceValue) -> SourceValue)
}

/// Internal protocol for EditorPool.
internal protocol _EditorProtocol: class {
	func reset()
	func commit()
}

/// `Editable` describes the requirement of an `Editor` bindable control.
public protocol Editable: _Editable {
	associatedtype Value: Equatable
	var value: Value { get set }
}

public protocol _Editable: class {
	func subscribeToChanges<SourceValue, TargetValue>(with editor: Editor<SourceValue, TargetValue>)
	func unsubscribeToChanges<SourceValue, TargetValue>(with editor: Editor<SourceValue, TargetValue>)
}
