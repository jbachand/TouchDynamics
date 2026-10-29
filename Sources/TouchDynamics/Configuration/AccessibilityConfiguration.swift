import Foundation
import CoreGraphics

/// Feedback used in place of motion when Reduce Motion is on.
public enum ReducedMotionBehavior: Sendable, Equatable {
    /// A non-moving highlight: the illumination appears under the finger and
    /// cross-fades out on release. No ripple travel, no deformation.
    case staticHighlight
    /// No feedback at all.
    case none
}

/// Configuration for accessibility adaptations.
public struct AccessibilityConfiguration: Sendable, Equatable {
    /// Replace motion with ``reducedMotionBehavior`` when Reduce Motion is on.
    public var respectsReduceMotion: Bool
    /// What to show instead of motion.
    public var reducedMotionBehavior: ReducedMotionBehavior
    /// Use a flat, higher-contrast highlight when Reduce Transparency is on.
    public var respectsReduceTransparency: Bool
    /// Opacity of the flat highlight used under Reduce Transparency.
    public var reducedTransparencyIntensity: CGFloat
    /// Disable deformation while VoiceOver is running so the focused element's
    /// geometry stays stable. Illumination and ripple remain.
    public var disablesDeformationForVoiceOver: Bool

    public init(
        respectsReduceMotion: Bool = true,
        reducedMotionBehavior: ReducedMotionBehavior = .staticHighlight,
        respectsReduceTransparency: Bool = true,
        reducedTransparencyIntensity: CGFloat = 0.28,
        disablesDeformationForVoiceOver: Bool = true
    ) {
        self.respectsReduceMotion = respectsReduceMotion
        self.reducedMotionBehavior = reducedMotionBehavior
        self.respectsReduceTransparency = respectsReduceTransparency
        self.reducedTransparencyIntensity = reducedTransparencyIntensity.clamped(to: 0...1)
        self.disablesDeformationForVoiceOver = disablesDeformationForVoiceOver
    }
}
