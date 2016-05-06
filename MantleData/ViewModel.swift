//
//  ViewModelType.swift
//  Galleon
//
//  Created by Ik ben anders on 15/9/2015.
//  Copyright © 2015 Ik ben anders. All rights reserved.
//

import Foundation
import CoreData

public protocol ViewModel {
	associatedtype MappingObject: Equatable
}
