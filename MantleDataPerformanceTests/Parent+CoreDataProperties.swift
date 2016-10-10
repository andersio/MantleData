//
//  Parent+CoreDataProperties.swift
//  MantleData
//
//  Created by Anders on 10/10/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

import Foundation
import CoreData


extension Parent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Parent> {
        return NSFetchRequest<Parent>(entityName: "Parent");
    }

    @NSManaged public var value: Int64
    @NSManaged public var children: NSSet?

}

// MARK: Generated accessors for children
extension Parent {

    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: Children)

    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: Children)

    @objc(addChildren:)
    @NSManaged public func addToChildren(_ values: NSSet)

    @objc(removeChildren:)
    @NSManaged public func removeFromChildren(_ values: NSSet)

}
