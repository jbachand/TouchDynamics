import Foundation
import CoreGraphics

/// How far the release wave travels.
public enum RippleExpansion: Sendable, Equatable {
    /// Travels until the wavefront has passed the farthest corner of the
    /// target's bounds (measured from the ripple origin).
    case fillBounds
    /// Travels to a fixed radius in points.
    case fixed(radius: CGFloat)
    /// Travels to a multiple of the illumination radius.
    case scaled(CGFloat)
}

/// The visual profile of the release wave.
public enum RippleProfile: Sendable, Equatable {
    /// An expanding soft disc that fades as it grows.
    case softGradient
    /// A thin, soft wavefront ring.
    case wavefront
    /// Both a soft disc and a leading wavefront ring.
    case combined
}

/// Where the ripple originates.
public enum RippleOrigin: Sendable, Equatable {
    /// The location where the finger lifted.
    case releaseLocation
    /// The location where the touch began.
    case initialLocation
}

/// Configuration for the wave emitted when the finger lifts.
///
/// The wave is modeled as `R(r, t) = B·e^(−λt) · exp(−(r − vt)² / 2w²)`; see
/// ``RippleWave`` for the exact timing functions.
public struct RippleConfiguration: Sendable, Equatable {
    /// Whether a ripple is emitted on release.
    public var isEnabled: Bool
    /// Total duration of the wave in seconds. The PRD range is 0.25–0.45 s.
    public var duration: TimeInterval
    /// How far the wave travels.
    public var expansion: RippleExpansion
    /// Disc, ring, or both.
    public var profile: RippleProfile
    /// Softness (Gaussian width) of the wavefront ring, in points.
    public var wavefrontWidth: CGFloat
    /// Decay rate λ of the opacity envelope over normalized time `t/duration`.
    /// Larger values fade earlier.
    public var decay: Double
    /// Peak opacity of the wave. `nil` uses `1.25 × illumination intensity`.
    public var peakIntensity: CGFloat?
    /// Where the wave starts.
    public var origin: RippleOrigin
    /// Color override. `nil` uses the illumination color.
    public var color: EffectColor?

    public init(
        isEnabled: Bool = true,
        duration: TimeInterval = 0.38,
        expansion: RippleExpansion = .fillBounds,
        profile: RippleProfile = .combined,
        wavefrontWidth: CGFloat = 28,
        decay: Double = 2.4,
        peakIntensity: CGFloat? = nil,
        origin: RippleOrigin = .releaseLocation,
        color: EffectColor? = nil
    ) {
        self.isEnabled = isEnabled
        self.duration = max(0.05, duration)
        self.expansion = expansion
        self.profile = profile
        self.wavefrontWidth = max(1, wavefrontWidth)
        self.decay = max(0.1, decay)
        self.peakIntensity = peakIntensity.map { $0.clamped(to: 0...1) }
        self.origin = origin
        self.color = color
    }

    /// Ripple disabled.
    public static let off = RippleConfiguration(isEnabled: false)
}
