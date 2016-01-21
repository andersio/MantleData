//
//  ReactiveCell.swift
//  Galleon
//
//  Created by Anders on 30/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import UIKit
import ReactiveCocoa

public protocol ReactiveView: class {
	typealias MappingViewModel: ViewModel
  var viewModel: MutableProperty<MappingViewModel?> { get }
}