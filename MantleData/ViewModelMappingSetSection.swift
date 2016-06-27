//
//  ViewModelSetSection.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

public struct ViewModelMappingSetSection<U: ViewModel>: ReactiveSetSection {
	public typealias Index = Int

	private let base: AnyReactiveSetSection<U.MappingObject>
	private let sectionNameTransform: ((ReactiveSetSectionName) -> ReactiveSetSectionName)?
	private let factory: (U.MappingObject) -> U

	public var name: ReactiveSetSectionName {
		return sectionNameTransform?(base.name) ?? base.name
	}

	public var startIndex: Int {
		return base.startIndex
	}

	public var endIndex: Int {
		return base.endIndex
	}

	public init(base: AnyReactiveSetSection<U.MappingObject>, factory: (U.MappingObject) -> U, sectionNameTransform: ((ReactiveSetSectionName) -> ReactiveSetSectionName)?) {
		self.base = base
		self.factory = factory
		self.sectionNameTransform = sectionNameTransform
	}

	public subscript(position: Int) -> U {
		return factory(base[position])
	}

	public subscript(subRange: Range<Int>) -> BidirectionalSlice<ViewModelMappingSetSection> {
		return BidirectionalSlice(base: self, bounds: subRange)
	}

	public func index(after i: Int) -> Int {
		return base.index(after: i)
	}

	public func index(before i: Int) -> Int {
		return base.index(before: i)
	}
}
