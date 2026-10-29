import Foundation
import CoreGraphics

/// Light or dark appearance, independent of UIKit for testability.
public enum EffectAppearanceStyle: Sendable, Equatable {
    case light
    case dark
}

/// The concrete, per-touch rendering plan derived from a configuration, the
/// host appearance and the accessibility status.
///
/// This is what renderers consume. Deriving it in one place guarantees that
/// Reduce Motion, Reduce Transparency and VoiceOver are honored identically by
/// Core Animation, Metal and SwiftUI.
public struct ResolvedEffectAppearance: Sendable, Equatable {
    /// How the illumination is drawn.
    public enum IlluminationStyle: Sendable, Equatable {
        /// Gaussian disc under the finger.
        case field(IlluminationField)
        /// Flat fill of the whole surface (Reduce Transparency).
        case flat(opacity: CGFloat)
        case none
    }

    /// How the release is drawn.
    public enum ReleaseStyle: Sendable, Equatable {
        /// Travelling wave.
        case wave(width: CGFloat, duration: TimeInterval, decay: Double, peak: CGFloat, profile: RippleProfile, expansion: RippleExpansion, origin: RippleOrigin)
        /// Non-moving cross-fade of the illumination over `duration`
        /// (Reduce Motion), with an optional flat flash.
        case staticFade(duration: TimeInterval, flashOpacity: CGFloat)
        case none
    }

    public var illumination: IlluminationStyle
    public var release: ReleaseStyle
    public var rampInDuration: TimeInterval
    public var fadeOutDuration: TimeInterval
    public var tracking: IlluminationTracking
    /// Core Image blend-mode filter name for the surface layer, or `nil`.
    public var compositingFilterName: String?
    /// Deformation to apply, or `nil` when disabled for this touch.
    public var elasticity: ElasticityConfiguration?
    public var isReducedMotion: Bool
    public var isReducedTransparency: Bool
    public var style: EffectAppearanceStyle

    /// Resolves a configuration for a touch.
    public init(
        configuration: TouchDynamicsConfiguration,
        style: EffectAppearanceStyle,
        accessibility: AccessibilityStatus
    ) {
        let a11y = configuration.accessibility
        let reduceMotion = a11y.respectsReduceMotion && accessibility.isReduceMotionEnabled
        let reduceTransparency = a11y.respectsReduceTransparency && accessibility.isReduceTransparencyEnabled
        let voiceOver = a11y.disablesDeformationForVoiceOver && accessibility.isVoiceOverRunning
        let silent = reduceMotion && a11y.reducedMotionBehavior == .none

        self.style = style
        self.isReducedMotion = reduceMotion
        self.isReducedTransparency = reduceTransparency
        self.rampInDuration = configuration.illumination.rampInDuration
        self.fadeOutDuration = configuration.illumination.fadeOutDuration
        self.tracking = reduceMotion ? .anchored : configuration.illumination.tracking

        let ill = configuration.illumination
        if !ill.isEnabled || silent {
            self.illumination = .none
        } else if reduceTransparency {
            self.illumination = .flat(opacity: a11y.reducedTransparencyIntensity)
        } else {
            self.illumination = .field(IlluminationField(configuration: ill))
        }

        let rip = configuration.ripple
        let peak = rip.peakIntensity ?? min(1, ill.intensity * 1.25)
        if !rip.isEnabled || silent {
            self.release = .none
        } else if reduceMotion || reduceTransparency {
            let flash = reduceTransparency ? a11y.reducedTransparencyIntensity * 0.6 : peak * 0.5
            self.release = .staticFade(duration: rip.duration, flashOpacity: flash)
        } else {
            self.release = .wave(
                width: rip.wavefrontWidth,
                duration: rip.duration,
                decay: rip.decay,
                peak: peak,
                profile: rip.profile,
                expansion: rip.expansion,
                origin: rip.origin
            )
        }

        switch ill.compositing {
        case .normal:
            self.compositingFilterName = nil
        case .multiply:
            self.compositingFilterName = "multiplyBlendMode"
        case .screen:
            self.compositingFilterName = "screenBlendMode"
        case .adaptive:
            self.compositingFilterName = style == .dark ? "screenBlendMode" : "multiplyBlendMode"
        }
        // A flat high-contrast highlight must not be blended away.
        if reduceTransparency { self.compositingFilterName = nil }

        let el = configuration.elasticity
        self.elasticity = (el.isEnabled && !reduceMotion && !voiceOver) ? el : nil
    }

    /// Whether the touch produces any visible feedback.
    public var isSilent: Bool {
        illumination == .none && release == .none && elasticity == nil
    }
}
