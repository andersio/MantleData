//
//  AnyReactiveSetBox.swift
//  MantleData
//
//  Created by Anders on 17/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import ReactiveCocoa

final internal class _AnyReactiveSetBoxBase<R: ReactiveSet>: _AnyReactiveSetBox<R.Generator.Element.Generator.Element> {
	private let set: R

	override var eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError> {
		return set.eventProducer.map { event in
			switch event {
			case .reloaded:
				return .reloaded

			case let .updated(changes):
				let insertedRows: [ReactiveSetIndexPath<AnyReactiveSetIndex, AnyReactiveSetIndex>]? = changes.insertedRows?.map { $0.typeErased() }
				let deletedRows = changes.deletedRows?.map { $0.typeErased() }
				let movedRows = changes.movedRows?.map { (from: $0.0.typeErased(), to: $0.1.typeErased()) }
				let updatedRows = changes.updatedRows?.map { $0.typeErased() }
				let insertedSections = changes.insertedSections?.map { AnyReactiveSetIndex(converting: $0) }
				let deletedSections = changes.deletedSections?.map { AnyReactiveSetIndex(converting: $0) }
				let reloadedSections = changes.reloadedSections?.map { AnyReactiveSetIndex(converting: $0) }

				let mappedChanges: ReactiveSetChanges<AnyReactiveSetIndex, AnyReactiveSetIndex>

				mappedChanges = ReactiveSetChanges(insertedRows: insertedRows,
					deletedRows: deletedRows,
					movedRows: movedRows,
					updatedRows: updatedRows,
					insertedSections: insertedSections,
					deletedSections: deletedSections,
					reloadedSections: reloadedSections)

				return ReactiveSetEvent.updated(mappedChanges)
			}
		}
	}

	init(_ set: R) {
		self.set = set
	}

	override func fetch() throws {
		try set.fetch()
	}

	override var startIndex: Index {
		return Index(converting: set.startIndex)
	}

	override var endIndex: Index {
		return Index(converting: set.endIndex)
	}

	override subscript(index: Index) -> AnyReactiveSetSection<R.Generator.Element.Generator.Element> {
		let index = R.Index(converting: index)
		return AnyReactiveSetSection(set[index])
	}

	override func generate() -> Generator {
		var i = self.startIndex
		return AnyReactiveSetIterator {
			if i < self.endIndex {
				defer { i = i.successor() }
				return self[i]
			} else {
				return nil
			}
		}
	}

	override func sectionName(of object: Generator.Element.Generator.Element) -> ReactiveSetSectionName? {
		return set.sectionName(of: object)
	}

	override func indexPath(of element: Generator.Element.Generator.Element) -> ReactiveSetIndexPath<Index, Generator.Element.Index>? {
		return set.indexPath(of: element)?.typeErased()
	}
}

internal class _AnyReactiveSetBox<E>: ReactiveSet {
	typealias Index = AnyReactiveSetIndex
	typealias Generator = AnyReactiveSetIterator<AnyReactiveSetSection<E>>

	var eventProducer: SignalProducer<ReactiveSetEvent<Index, Generator.Element.Index>, NoError> {
		_abstractMethod_subclassMustImplement()
	}

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	func fetch() throws {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> AnyReactiveSetSection<E> {
		_abstractMethod_subclassMustImplement()
	}

	func generate() -> Generator {
		_abstractMethod_subclassMustImplement()
	}
	
	func sectionName(of object: E) -> ReactiveSetSectionName? {
		_abstractMethod_subclassMustImplement()
	}

	func indexPath(of element: E) -> ReactiveSetIndexPath<Index, Generator.Element.Index>? {
		_abstractMethod_subclassMustImplement()
	}
}

final internal class _AnyReactiveSetSectionBoxBase<S: ReactiveSetSection>: _AnyReactiveSetSectionBox<S.Generator.Element> {
	private let wrappedSection: S

	override var name: ReactiveSetSectionName {
		return wrappedSection.name
	}

	override var startIndex: Index {
		return Index(converting: wrappedSection.startIndex)
	}

	override var endIndex: Index {
		return Index(converting: wrappedSection.endIndex)
	}

	init(_ set: S) {
		self.wrappedSection = set
	}

	override subscript(index: Index) -> S.Generator.Element {
		let index = S.Index(converting: index)
		return wrappedSection[index]
	}

	override func generate() -> Generator {
		var i = self.startIndex
		return AnyReactiveSetSectionIterator {
			if i < self.endIndex {
				defer { i = i.successor() }
				return self[i]
			}
			return nil
		}
	}
}

internal class _AnyReactiveSetSectionBox<E>: ReactiveSetSection {
	typealias Entity = E

	typealias Index = AnyReactiveSetIndex
	typealias Generator = AnyReactiveSetSectionIterator<E>

	var name: ReactiveSetSectionName {
		_abstractMethod_subclassMustImplement()
	}

	var startIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	var endIndex: Index {
		_abstractMethod_subclassMustImplement()
	}

	subscript(index: Index) -> E {
		_abstractMethod_subclassMustImplement()
	}

	func generate() -> Generator {
		_abstractMethod_subclassMustImplement()
	}
}