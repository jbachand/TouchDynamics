import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A snapshot of the accessibility settings that change how effects render.
///
/// Resolved at touch-down so a setting toggled mid-session is picked up by the
/// next touch without observers.
public struct AccessibilityStatus: Sendable, Equatable {
    public var isReduceMotionEnabled: Bool
    public var isReduceTransparencyEnabled: Bool
    public var isVoiceOverRunning: Bool

    public init(isReduceMotionEnabled: Bool = false, isReduceTransparencyEnabled: Bool = false, isVoiceOverRunning: Bool = false) {
        self.isReduceMotionEnabled = isReduceMotionEnabled
        self.isReduceTransparencyEnabled = isReduceTransparencyEnabled
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    /// Nothing enabled.
    public static let none = AccessibilityStatus()

    #if canImport(UIKit)
    /// The device's current settings.
    @MainActor
    public static var current: AccessibilityStatus {
        AccessibilityStatus(
            isReduceMotionEnabled: UIAccessibility.isReduceMotionEnabled,
            isReduceTransparencyEnabled: UIAccessibility.isReduceTransparencyEnabled,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning
        )
    }
    #endif
}
