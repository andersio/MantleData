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

public protocol CocoaBridgeable {
	associatedtype Inner
  init(cocoaValue: AnyObject?)
  var cocoaValue: AnyObject? { get }
}

// String

extension String: CocoaBridgeable {
	public typealias Inner = String

  public var cocoaValue: AnyObject? {
    return self
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init(cocoaValue as! String)
  }
}

// Bool

extension Bool: CocoaBridgeable {
	public typealias Inner = Bool

  public var cocoaValue: AnyObject? {
    return NSNumber(bool: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).boolValue)
  }
}

// Signed Integers

extension Int16: CocoaBridgeable {
	public typealias Inner = Int16

  public var cocoaValue: AnyObject? {
    return NSNumber(short: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).shortValue)
  }
}

extension Int32: CocoaBridgeable {
	public typealias Inner = Int32

  public var cocoaValue: AnyObject? {
    return NSNumber(int: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).intValue)
  }
}

extension Int64: CocoaBridgeable {
	public typealias Inner = Int64

  public var cocoaValue: AnyObject? {
    return NSNumber(longLong: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).longLongValue)
  }
}

extension Int: CocoaBridgeable {
	public typealias Inner = Int

  public var cocoaValue: AnyObject? {
    return NSNumber(integer: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).integerValue)
  }
}

// Unsigned Integers
// UInt and UInt64 are excluded.

extension UInt16: CocoaBridgeable {
	public typealias Inner = UInt16

  public var cocoaValue: AnyObject? {
    return NSNumber(unsignedShort: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).unsignedShortValue)
  }
}

extension UInt32: CocoaBridgeable {
	public typealias Inner = UInt32

  public var cocoaValue: AnyObject? {
    return NSNumber(unsignedInt: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).unsignedIntValue)
  }
}

extension Int8: CocoaBridgeable {
	public typealias Inner = Int8

	public var cocoaValue: AnyObject? {
		return NSNumber(char: self)
	}

	public init(cocoaValue: AnyObject?) {
		self.init((cocoaValue as! NSNumber).charValue)
	}
}

extension UInt8: CocoaBridgeable {
	public typealias Inner = UInt8

	public var cocoaValue: AnyObject? {
		return NSNumber(unsignedChar: self)
	}

	public init(cocoaValue: AnyObject?) {
		self.init((cocoaValue as! NSNumber).unsignedCharValue)
	}
}

// Floating Points

extension Float: CocoaBridgeable {
	public typealias Inner = Float

  public var cocoaValue: AnyObject? {
    return NSNumber(float: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).floatValue)
  }
}

extension Double: CocoaBridgeable {
	public typealias Inner = Double

  public var cocoaValue: AnyObject? {
    return NSNumber(double: self)
  }
  
  public init(cocoaValue: AnyObject?) {
    self.init((cocoaValue as! NSNumber).doubleValue)
  }
}

extension Optional: CocoaBridgeable {
	public typealias Inner = Wrapped

	public var cocoaValue: AnyObject? {
		guard let value = self else {
			return nil
		}
		switch value {
		case _ as NSNull: return nil
		case let value as Int: return value.cocoaValue
		case let value as String: return value.cocoaValue
		case let value as Double: return value.cocoaValue
		case let value as Bool: return value.cocoaValue
		case let value as Float: return value.cocoaValue
		case let value as Int64: return value.cocoaValue
		case let value as Int32: return value.cocoaValue
		case let value as UInt32: return value.cocoaValue
		case let value as UInt16: return value.cocoaValue
		case let value as Int16: return value.cocoaValue
		case let value as UInt8: return value.cocoaValue
		case let value as Int8: return value.cocoaValue
		default: preconditionFailure("Unsupported data type.")
		}
	}

	public init(cocoaValue: AnyObject?) {
		switch cocoaValue {
		case .None:
			self = nil

		default:
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
}

// Special Data Types

extension CGFloat: CocoaBridgeable {
	public typealias Inner = CGFloat

  public var cocoaValue: AnyObject? {
    #if CGFLOAT_IS_DOUBLE
    return NSNumber(double: Double(self))
    #else
    return NSNumber(float: Float(self))
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