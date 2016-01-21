//
//  Repository.swift
//  Galleon
//
//  Created by Ik ben anders on 7/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import ReactiveCocoa

public final class ViewModelSet<U: ViewModel>: Base {
	public let sectionNameTransform: ((Int, ReactiveSetSectionName) -> String?)?
  private let set: _AnyReactiveSetBox<U.MappingObject>
	private let factory: U.MappingObject -> U
  
  public var eventProducer: SignalProducer<ReactiveSetEvent, NoError> {
		return set.eventProducer
  }

	public init<R: ReactiveSet where R.Generator.Element.Generator.Element == U.MappingObject>(_ set: R, factory: U.MappingObject -> U, sectionNameTransform: ((Int, ReactiveSetSectionName) -> String?)? = nil) {
    self.set = _AnyReactiveSetBoxBase(set)
		self.factory = factory
		self.sectionNameTransform = sectionNameTransform

    super.init()
	}

	public var isFetched: Bool {
		return set.isFetched
	}

	public var objectsCount: Int {
		return set.reduce(0, combine: { $0 + Int($1.count) })
	}

  public var sectionCount: Int {
    return Int(set.count)
  }

  public func rowCountFor(section: Int) -> Int {
    return Int(set[section].count)
  }

	public func fetch() throws {
		try set.fetch()
	}

  public func nameFor(section: Int) -> String? {
		let sectionName = set[section].name
		return sectionNameTransform?(section, sectionName) ?? sectionName.value
  }

	public subscript(indexPath: NSIndexPath) -> U {
    let model = set[indexPath]
    let viewModel = factory(model)
    return viewModel
  }
}

extension ViewModelSet where U.MappingObject: Object {
	public convenience init(_ resultProducer: ResultProducer<U.MappingObject>, factory: U.MappingObject -> U) {
		self.init(resultProducer.objectSet, factory: factory)
	}
}