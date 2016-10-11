//
//  Children+CoreDataProperties.swift
//  MantleData
//
//  Created by Anders on 12/10/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import CoreData


extension Children {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Children> {
        return NSFetchRequest<Children>(entityName: "Children");
    }

    @NSManaged public var value: Int64
    @NSManaged public var group: String?
    @NSManaged public var parent: Parent?

}
