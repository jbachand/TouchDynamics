import Foundation

/// Identifies one touch for the lifetime of its touch sequence.
public struct TouchIdentifier: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Derives an identifier from an object's identity.
    ///
    /// Do not use this for `UITouch`: UIKit reuses touch objects across the
    /// taps of a multi-tap sequence, so a double tap would collide with the
    /// session still releasing from the first tap. The UIKit integration
    /// assigns a fresh identifier at every touch-down instead.
    public init(object: AnyObject) {
        self.rawValue = UInt(bitPattern: Int(bitPattern: ObjectIdentifier(object)))
    }

    public var description: String { "touch#\(rawValue)" }
}
