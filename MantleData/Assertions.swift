//
//  Assertions.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

func _abstractMethod_subclassMustImplement(_ name: String = #function) -> Never  {
	fatalError("Abstract method `\(name)` should have been overriden by a subclass.")
}

func _unimplementedMethod(_ name: String = #function) -> Never  {
	fatalError("Method `\(name)` is not implemented.")
}
