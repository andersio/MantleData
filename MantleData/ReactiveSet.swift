//
//  ReactiveSet.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

/// ReactiveSet

public protocol ReactiveSetGenerator: GeneratorType {
	typealias Element: ReactiveSetSection
}

public struct AnyReactiveSetIterator<S: ReactiveSetSection>: ReactiveSetGenerator {
	public typealias Element = S

	private let generator: () -> Element?

	public init(generator: () -> Element?) {
		self.generator = generator
	}

	public mutating func next() -> Element? {
		return generator()
	}
}

public protocol ReactiveSet: class, CollectionType {
	typealias Generator: ReactiveSetGenerator
	typealias Index: ReactiveSetIndex

	var eventProducer: SignalProducer<ReactiveSetEvent, NoError> { get }
	var isFetched: Bool { get }

	func fetch() throws
}

extension ReactiveSet {
	public var eventSignal: Signal<ReactiveSetEvent, NoError> {
		var extractedSignal: Signal<ReactiveSetEvent, NoError>!
		eventProducer.startWithSignal { signal, _ in
			extractedSignal = signal
		}
		return extractedSignal
	}
}

extension ReactiveSet where Index: ReactiveSetIndex {
	public subscript(index: Int) -> Generator.Element {
		return self[Index(reactiveSetIndex: index)]
	}
}

extension ReactiveSet where Index: ReactiveSetIndex, Generator.Element.Index: ReactiveSetIndex {
	public subscript(indexPath: NSIndexPath) -> Generator.Element.Generator.Element {
		return self[Index(reactiveSetIndex: indexPath.section)][Generator.Element.Index(reactiveSetIndex: indexPath.row)]
	}
}

/// Events of ReactiveSet

public enum ReactiveSetEvent {
	case Reloaded
	case Updated(ReactiveSetChanges)
}

extension ReactiveSetEvent: CustomStringConvertible {
	public var description: String {
		switch self {
		case .Reloaded:
			return "ReactiveSetEvent.Reloaded"

		case let .Updated(changes):
			return "ReactiveSetEvent.Updated [BEGIN]\n\(changes)\n[END]"
		}
	}
}

/// Change Descriptor of ReactiveSet

public struct ReactiveSetChanges {
	public let indexPathsOfDeletedRows: [NSIndexPath]?
	public let indexPathsOfInsertedRows: [NSIndexPath]?
	public let indexPathsOfMovedRows: [(NSIndexPath, NSIndexPath)]?
	public let indexPathsOfUpdatedRows: [NSIndexPath]?

	public let indiceOfInsertedSections: NSIndexSet?
	public let indiceOfDeletedSections: NSIndexSet?
	public let indiceOfReloadedSections: NSIndexSet?

	public init(indexPathsOfDeletedRows: [NSIndexPath]? = nil, indexPathsOfInsertedRows: [NSIndexPath]? = nil, indexPathsOfMovedRows: [(NSIndexPath, NSIndexPath)]? = nil, indexPathsOfUpdatedRows: [NSIndexPath]? = nil, indiceOfInsertedSections: NSIndexSet? = nil, indiceOfDeletedSections: NSIndexSet? = nil, indiceOfReloadedSections: NSIndexSet? = nil) {
		func makeImmutable(indexSet: NSIndexSet?) -> NSIndexSet? {
			if let indexSet = indexSet {
				return indexSet is NSMutableIndexSet ? NSIndexSet(indexSet: indexSet) : indexSet
			} else {
				return nil
			}
		}

		self.indexPathsOfInsertedRows = indexPathsOfInsertedRows
		self.indexPathsOfDeletedRows = indexPathsOfDeletedRows
		self.indexPathsOfMovedRows = indexPathsOfMovedRows
		self.indexPathsOfUpdatedRows = indexPathsOfUpdatedRows
		self.indiceOfDeletedSections = makeImmutable(indiceOfDeletedSections)
		self.indiceOfInsertedSections = makeImmutable(indiceOfInsertedSections)
		self.indiceOfReloadedSections = makeImmutable(indiceOfReloadedSections)
	}

	public init(appendingIndex index: Int, changes: ReactiveSetChanges) {
		self.init(indexPathsOfDeletedRows: changes.indexPathsOfDeletedRows?.appendIndex(index),
			indexPathsOfInsertedRows: changes.indexPathsOfInsertedRows?.appendIndex(index),
			indexPathsOfMovedRows: changes.indexPathsOfMovedRows?.appendIndex(index),
			indexPathsOfUpdatedRows: changes.indexPathsOfUpdatedRows?.appendIndex(index))
	}
}

extension ReactiveSetChanges: CustomStringConvertible {
	public var description: String {
		// NOTE: explicitly state type to mitigate slow compile time type inference
		return (["ReactiveSetChanges" as String,
			indexPathsOfInsertedRows.map { "> \($0.count) row(s) inserted\n\($0._toString)" } ?? "" as String,
			indexPathsOfDeletedRows.map { "> \($0.count) row(s) deleted\n\($0._toString)" } ?? "" as String,
			indexPathsOfMovedRows.map { "> \($0.count) row(s) moved\n\($0._toString)" } ?? "" as String,
			indexPathsOfUpdatedRows.map { "> \($0.count) row(s) updated\n\($0._toString)" } ?? "" as String,
			indiceOfInsertedSections.map { "> \($0.count) section(s) inserted\n\($0._toString)" } ?? "" as String,
			indiceOfDeletedSections.map { "> \($0.count) section(s) deleted\n\($0._toString)" } ?? "" as String] as [String])
			.filter { !$0.isEmpty }
			.joinWithSeparator("\n")
	}
}



/// Section of ReactiveSet

public protocol ReactiveSetSection: CollectionType {
	typealias Index: ReactiveSetIndex

	var name: ReactiveSetSectionName { get }
}

public func == <S: ReactiveSetSection>(left: S, right: S) -> Bool {
	return left.name == right.name
}

extension ReactiveSetSection where Index: ReactiveSetIndex {
	public subscript(index: Int) -> Generator.Element {
		return self[Index(reactiveSetIndex: index)]
	}
}

/// Index of ReactiveSet

public protocol ReactiveSetIndex: RandomAccessIndexType {
	init<I: ReactiveSetIndex>(reactiveSetIndex: I)
	var intMaxValue: IntMax { get }
}

extension Int: ReactiveSetIndex {
	public init<I: ReactiveSetIndex>(reactiveSetIndex index: I) {
		self = Int(index.intMaxValue)
	}

	public var intMaxValue: IntMax {
		return IntMax(self)
	}
}

public struct AnyReactiveSetIndex: ReactiveSetIndex {
	public typealias Distance = IntMax
	public let intMaxValue: Distance

	public init(_ base: Distance) {
		intMaxValue = base
	}

	public init<I: ReactiveSetIndex>(reactiveSetIndex index: I) {
		intMaxValue = index.intMaxValue
	}

	public func successor() -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intMaxValue + 1)
	}

	public func predecessor() -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intMaxValue - 1)
	}

	public func advancedBy(n: Distance) -> AnyReactiveSetIndex {
		return AnyReactiveSetIndex(intMaxValue + n)
	}

	public func distanceTo(end: AnyReactiveSetIndex) -> Distance {
		return end.intMaxValue - intMaxValue
	}
}

/// Section Name of ReactiveSet

public struct ReactiveSetSectionName: Hashable {
	public let value: String?

	public init(_ value: String?) {
		self.value = value
	}

	public var hashValue: Int {
		return value?.hashValue ?? 0
	}

	/// `nil` is defined as the smallest of all.
	public func compareTo(otherName: ReactiveSetSectionName) -> NSComparisonResult {
		if let value = value, otherValue = otherName.value {
			return value.compare(otherValue)
		}

		if value == nil {
			// (nil) compare to (otherName)
			return .OrderedAscending
		}

		if otherName.value == nil {
			// (self) compare to (nil)
			return .OrderedDescending
		}

		// (nil) compare to (nil)
		return .OrderedSame
	}
}

public func ==(lhs: ReactiveSetSectionName, rhs: ReactiveSetSectionName) -> Bool {
	return lhs.value == rhs.value
}