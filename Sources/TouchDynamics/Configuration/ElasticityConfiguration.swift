import Foundation
import CoreGraphics

/// The geometric model used for elastic deformation.
public enum DeformationMode: Sendable, Equatable {
    /// Scale about the view's center.
    case uniformScale
    /// Scale about the touch point, so the content appears to yield under the
    /// finger. This is the default.
    case anchoredScale
    /// A small affine shear driven by finger displacement.
    case shear
    /// Shader-based localized displacement.
    ///
    /// Reserved for the Metal renderer. In v1.0 this mode renders as
    /// ``anchoredScale`` on every renderer; see the roadmap in the README.
    case displacement
}

/// Whether a press compresses or expands the content.
public enum PressResponse: Sendable, Equatable {
    case compress
    case expand
}

/// Configuration for elastic deformation of the touched content.
///
/// Release restores the resting geometry with a damped spring
/// `m·ẍ + c·ẋ + k·x = 0`, where `c = 2ζ√(km)` and ζ is ``damping``.
/// Deformation is applied as a transform and never changes layout.
public struct ElasticityConfiguration: Sendable, Equatable {
    /// Whether deformation is applied at all.
    public var isEnabled: Bool
    /// Press deformation as a fraction of size (0.025 = 2.5 %).
    public var strength: CGFloat
    /// Geometric model.
    public var mode: DeformationMode
    /// Expand (default) or compress on press.
    public var response: PressResponse
    /// Directional tension: how strongly finger displacement stretches or
    /// shears the content, as a fraction of size per full-size displacement.
    public var tension: CGFloat
    /// Hard clamp on any single deformation component (scale delta, shear).
    public var maximumDeformation: CGFloat
    /// Spring damping ratio ζ. `1` is critically damped; lower values overshoot.
    public var damping: Double
    /// Spring stiffness `k`.
    public var stiffness: Double
    /// Spring mass `m`.
    public var mass: Double
    /// Duration of the press-in ease.
    public var pressDuration: TimeInterval

    public init(
        isEnabled: Bool = true,
        strength: CGFloat = 0.025,
        mode: DeformationMode = .anchoredScale,
        response: PressResponse = .expand,
        tension: CGFloat = 0.06,
        maximumDeformation: CGFloat = 0.08,
        damping: Double = 0.72,
        stiffness: Double = 320,
        mass: Double = 1,
        pressDuration: TimeInterval = 0.12
    ) {
        self.isEnabled = isEnabled
        self.strength = strength.clamped(to: 0...0.5)
        self.mode = mode
        self.response = response
        self.tension = tension.clamped(to: 0...1)
        self.maximumDeformation = maximumDeformation.clamped(to: 0...0.5)
        self.damping = damping.clamped(to: 0.05...4)
        self.stiffness = stiffness.clamped(to: 1...5000)
        self.mass = mass.clamped(to: 0.01...100)
        self.pressDuration = max(0, pressDuration)
    }

    /// The spring that restores the resting geometry on release.
    public var spring: SpringSolver {
        SpringSolver(mass: mass, stiffness: stiffness, dampingRatio: damping)
    }

    /// Deformation disabled.
    public static let off = ElasticityConfiguration(isEnabled: false)
}
