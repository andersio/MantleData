//
//  Assertions.swift
//  MantleData
//
//  Created by Anders on 13/1/2016.
//  Copyright © 2016 Anders. All rights reserved.
//

@noreturn func _abstractMethod_subclassMustImplement(name: String = __FUNCTION__) {
	fatalError("Abstract method `\(name)` should have been overriden by a subclass.")
}

@noreturn func _unimplementedMethod(name: String = __FUNCTION__) {
	fatalError("Method `\(name)` is not implemented.")
}