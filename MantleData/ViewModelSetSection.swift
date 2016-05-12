//
//  ViewModelSetSection.swift
//  MantleData
//
//  Created by Anders on 7/5/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

public struct ViewModelSetSection<U: ViewModel> {
	public typealias Index = Int
	public typealias Generator = AnyReactiveSetSectionIterator<U>

	private let wrappingSection: AnyReactiveSetSection<U.MappingObject>
	private unowned var parentSet: ViewModelSet<U>

	public init(_ section: AnyReactiveSetSection<U.MappingObject>, in set: ViewModelSet<U>) {
		wrappingSection = section
		parentSet = set
	}
}

extension ViewModelSetSection: ReactiveSetSection {
	public var name: ReactiveSetSectionName {
		return parentSet.sectionNameMapper?(wrappingSection.name) ?? wrappingSection.name
	}

	public var startIndex: Index {
		return wrappingSection.startIndex
	}

	public var endIndex: Index {
		return wrappingSection.endIndex
	}

	public subscript(position: Index) -> Generator.Element {
		return parentSet.factory(wrappingSection[position])
	}

	public func generate() -> Generator {
		var iterator = startIndex
		let limit = endIndex

		return AnyReactiveSetSectionIterator {
			defer { iterator = iterator.successor() }
			return iterator < limit ? self[iterator] : nil
		}
	}
}