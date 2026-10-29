import Foundation

/// Identifies one touch for the lifetime of its touch sequence.
public struct TouchIdentifier: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Derives a stable identifier from an object's identity (for example a
    /// `UITouch`, which stays the same instance for a whole touch sequence).
    public init(object: AnyObject) {
        self.rawValue = UInt(bitPattern: Int(bitPattern: ObjectIdentifier(object)))
    }

    public var description: String { "touch#\(rawValue)" }
}
