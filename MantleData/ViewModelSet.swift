//
//  ViewModelSet.swift
//  MantleData
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

public final class ViewModelSet<U: ViewModel>: Base {
	public var sectionNameTransform: ((Int, ReactiveSetSectionName) -> String?)?
  private let set: _AnyReactiveSetBox<U.MappingObject>
	private let factory: U.MappingObject -> U
  
  public var eventProducer: SignalProducer<ReactiveSetEvent<AnyReactiveSetIndex, AnyReactiveSetIndex>, NoError> {
		return set.eventProducer
  }

	public init<R: ReactiveSet where R.Generator.Element.Generator.Element == U.MappingObject>(_ set: R, factory: U.MappingObject -> U) {
    self.set = _AnyReactiveSetBoxBase(set)
		self.factory = factory

    super.init()
	}

	public var numberOfObjects: Int {
		return set.reduce(0, combine: { $0 + Int($1.count) })
	}

  public var numberOfSections: Int {
    return Int(set.count)
  }

  public func numberOfRows(for sectionIndex: Int) -> Int {
		let index = AnyReactiveSetIndex(converting: sectionIndex)
    return Int(set[index].count)
  }

	public func fetch() throws {
		try set.fetch()
	}

  public func sectionName(for sectionIndex: Int) -> String? {
		let index = AnyReactiveSetIndex(converting: sectionIndex)
		let sectionName = set[index].name
		return sectionNameTransform?(sectionIndex, sectionName) ?? sectionName.value
  }

	public subscript(indexPath: NSIndexPath) -> U {
		let model = set[AnyReactiveSetIndex(converting: indexPath.section), row: AnyReactiveSetIndex(converting: indexPath.row)]
    let viewModel = factory(model)
    return viewModel
  }
}