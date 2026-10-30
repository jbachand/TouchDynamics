import Foundation
import CoreGraphics

/// How the illumination field follows the finger while it is down.
public enum IlluminationTracking: Sendable, Equatable {
    /// The field stays where the touch began.
    case anchored
    /// The field follows the finger, smoothed over `smoothing` seconds.
    case follow(smoothing: TimeInterval)

    /// Follows the finger with the default smoothing (80 ms).
    public static let follow = IlluminationTracking.follow(smoothing: 0.08)
}

/// Where the effect surface is placed relative to the host content.
public enum EffectPlacement: Sendable, Equatable {
    /// UIKit: beneath content for plain views, above content for `UIControl`s.
    /// SwiftUI: above content.
    case automatic
    /// Beneath the host's subviews / SwiftUI content.
    ///
    /// In SwiftUI this uses `.background`, so an opaque background applied
    /// *before* `touchDynamics()` will hide the effect; apply the modifier
    /// before such backgrounds, or use ``aboveContent``.
    case beneathContent
    /// Above the host's content. Hit-testing is never affected.
    case aboveContent
}

/// How the effect surface is composited onto the content behind it.
public enum EffectCompositing: Sendable, Equatable {
    /// Standard source-over alpha compositing.
    case normal
    /// `screen` for a light color (the default white light brightens what it
    /// covers), `multiply` for a dark color (a shade darkens it). Either way
    /// an effect placed above the content reads as acting on the surface.
    case adaptive
    /// Always multiply (darkening).
    case multiply
    /// Always screen (brightening).
    case screen
}

/// Configuration for the illumination field shown while a finger is down.
///
/// The field is a Gaussian disc centered on the touch:
/// `I(r) = A · exp(-r² / 2σ²)` with `σ = falloff · radius`, windowed to zero at
/// `radius`. See ``IlluminationField``.
public struct IlluminationConfiguration: Sendable, Equatable {
    /// Whether illumination is drawn at all.
    public var isEnabled: Bool
    /// The light color. Defaults to ``EffectColor/adaptive``.
    public var color: EffectColor
    /// Peak opacity of the field at the touch point, `0...1`.
    public var intensity: CGFloat
    /// Visible radius of the field in points.
    public var radius: CGFloat
    /// Gaussian width as a fraction of ``radius`` (`σ / radius`), `0...1`.
    public var falloff: CGFloat
    /// Time for the field to reach full intensity after touch-down.
    public var rampInDuration: TimeInterval
    /// Time for the field to fade when a touch is cancelled or dragged away.
    public var fadeOutDuration: TimeInterval
    /// Whether and how the field follows the finger.
    public var tracking: IlluminationTracking
    /// Placement relative to the host content.
    public var placement: EffectPlacement
    /// Compositing mode onto the content behind the surface.
    public var compositing: EffectCompositing

    public init(
        isEnabled: Bool = true,
        color: EffectColor = .adaptive,
        intensity: CGFloat = 0.16,
        radius: CGFloat = 110,
        falloff: CGFloat = 0.45,
        rampInDuration: TimeInterval = 0.09,
        fadeOutDuration: TimeInterval = 0.18,
        tracking: IlluminationTracking = .follow,
        placement: EffectPlacement = .automatic,
        compositing: EffectCompositing = .adaptive
    ) {
        self.isEnabled = isEnabled
        self.color = color
        self.intensity = intensity.clamped(to: 0...1)
        self.radius = max(1, radius)
        self.falloff = falloff.clamped(to: 0.05...1)
        self.rampInDuration = max(0, rampInDuration)
        self.fadeOutDuration = max(0, fadeOutDuration)
        self.tracking = tracking
        self.placement = placement
        self.compositing = compositing
    }

    /// Illumination disabled.
    public static let off = IlluminationConfiguration(isEnabled: false)
}
