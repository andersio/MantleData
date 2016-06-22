//
//  CocoaBridgeable.swift
//  MantleData
//
//  Created by Anders on 29/11/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

#if os(iOS)
	import UIKit
#elseif os(OSX)
	import Cocoa
#endif

public protocol _CocoaBridgeable {
	/// Unconditionally bridge the supplied value to `Self`.
	init(cocoaValue: AnyObject?)

	/// Bridge `self` to an Objective-C type.
	var cocoaValue: AnyObject? { get }
}

public protocol CocoaBridgeable: _CocoaBridgeable {
	associatedtype _Inner
}

// String

extension String: CocoaBridgeable {
	public typealias _Inner = String

  public var cocoaValue: AnyObject? {
    return self
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init(cocoaValue as! String)
  }
}

// Bool

extension Bool: CocoaBridgeable {
	public typealias _Inner = Bool

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).boolValue)
  }
}

// Signed Integers

extension Int16: CocoaBridgeable {
	public typealias _Inner = Int16

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).int16Value)
  }
}

extension Int32: CocoaBridgeable {
	public typealias _Inner = Int32

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).int32Value)
  }
}

extension Int64: CocoaBridgeable {
	public typealias _Inner = Int64

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).int64Value)
  }
}

extension Int: CocoaBridgeable {
	public typealias _Inner = Int

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).intValue)
  }
}

// Unsigned Integers
// UInt and UInt64 are excluded.

extension UInt16: CocoaBridgeable {
	public typealias _Inner = UInt16

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).uint16Value)
  }
}

extension UInt32: CocoaBridgeable {
	public typealias _Inner = UInt32

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).uint32Value)
  }
}

extension Int8: CocoaBridgeable {
	public typealias _Inner = Int8

	public var cocoaValue: AnyObject? {
		return NSNumber(value: self)
	}

	public init(cocoaValue: AnyObject?) {
		self.init((cocoaValue as! NSNumber).int8Value)
	}
}

extension UInt8: CocoaBridgeable {
	public typealias _Inner = UInt8

	public var cocoaValue: AnyObject? {
		return NSNumber(value: self)
	}

	public init(cocoaValue: AnyObject?) {
		self.init((cocoaValue as! NSNumber).uint8Value)
	}
}

// Floating Points

extension Float: CocoaBridgeable {
	public typealias _Inner = Float

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).floatValue)
  }
}

extension Double: CocoaBridgeable {
	public typealias _Inner = Double

  public var cocoaValue: AnyObject? {
    return NSNumber(value: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).doubleValue)
  }
}

extension Optional: CocoaBridgeable {
	public typealias _Inner = Wrapped

	public var cocoaValue: AnyObject? {
		guard let value = self else {
			return nil
		}

		if case let value as _CocoaBridgeable = value {
			return value.cocoaValue
		}

		preconditionFailure("Unsupported data type.")
	}

	public init(cocoaValue: AnyObject?) {
		guard let cocoaValue = cocoaValue else {
			self = nil
			return
		}

		switch Wrapped.self {
			case is NSNull.Type: self = nil
			case is Int.Type:		 self = (Int(cocoaValue: cocoaValue) as! Wrapped)
			case is String.Type: self = (String(cocoaValue: cocoaValue) as! Wrapped)
			case is Double.Type: self = (Double(cocoaValue: cocoaValue) as! Wrapped)
			case is Bool.Type:	 self = (Bool(cocoaValue: cocoaValue) as! Wrapped)
			case is Float.Type:	 self = (Float(cocoaValue: cocoaValue) as! Wrapped)
			case is Int64.Type:  self = (Int64(cocoaValue: cocoaValue) as! Wrapped)
			case is Int32.Type:  self = (Int32(cocoaValue: cocoaValue) as! Wrapped)
			case is UInt32.Type: self = (UInt32(cocoaValue: cocoaValue) as! Wrapped)
			case is UInt16.Type: self = (UInt16(cocoaValue: cocoaValue) as! Wrapped)
			case is Int16.Type:  self = (Int16(cocoaValue: cocoaValue) as! Wrapped)
			case is UInt8.Type:  self = (UInt8(cocoaValue: cocoaValue) as! Wrapped)
			case is Int8.Type:   self = (Int8(cocoaValue: cocoaValue) as! Wrapped)
			default: preconditionFailure("Unsupported data type.")
		}
	}
}

// Special Data Types

extension CGFloat: CocoaBridgeable {
	public typealias _Inner = CGFloat

  public var cocoaValue: AnyObject? {
    #if CGFLOAT_IS_DOUBLE
    return NSNumber(double: Double(self))
    #else
    return NSNumber(value: Float(self))
    #endif
  }
  
  public init(cocoaValue: AnyObject?) {
    #if CGFLOAT_IS_DOUBLE
    self.init((cocoaValue as! NSNumber).doubleValue)
    #else
    self.init((cocoaValue as! NSNumber).floatValue)
    #endif
  }
}
