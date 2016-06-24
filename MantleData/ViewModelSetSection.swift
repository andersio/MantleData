//
//  ViewModelSetSection.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

public struct ViewModelSetSection<U: ViewModel>: ReactiveSetSection {
	public typealias Index = Int
	public typealias Iterator = DefaultReactiveSetSectionIterator<U>

	private let wrappingSection: AnyReactiveSetSection<U.MappingObject>
	private unowned var parentSet: ViewModelSet<U>

	public var name: ReactiveSetSectionName {
		return parentSet.sectionNameMapper?(wrappingSection.name) ?? wrappingSection.name
	}

	public var startIndex: Int {
		return wrappingSection.startIndex
	}

	public var endIndex: Int {
		return wrappingSection.endIndex
	}

	public init(_ section: AnyReactiveSetSection<U.MappingObject>, in set: ViewModelSet<U>) {
		wrappingSection = section
		parentSet = set
	}

	public subscript(position: Int) -> U {
		return parentSet.factory(wrappingSection[position])
	}

	public subscript(subRange: Range<Int>) -> BidirectionalSlice<ViewModelSetSection> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func makeIterator() -> DefaultReactiveSetSectionIterator<U> {
		return DefaultReactiveSetSectionIterator(for: self)
	}

	public func index(after i: Int) -> Int {
		return i + 1
	}

	public func index(before i: Int) -> Int {
		return i - 1
	}
}
