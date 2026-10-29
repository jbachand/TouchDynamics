import Foundation
import CoreGraphics

public extension TouchDynamicsConfiguration {
    /// The default configuration. Identical to ``fluid``.
    static let `default` = TouchDynamicsConfiguration.fluid

    /// Soft illumination, a quiet ripple, and minimal deformation.
    static let subtle = TouchDynamicsConfiguration(
        illumination: .init(intensity: 0.10, radius: 90, falloff: 0.5, rampInDuration: 0.1),
        ripple: .init(duration: 0.3, profile: .softGradient, decay: 3.0),
        elasticity: .init(strength: 0.012, tension: 0.03, damping: 0.85, stiffness: 380)
    )

    /// Bright ripple and gentle directional elasticity. This reproduces the
    /// comment-row interaction the SDK was specified against.
    static let fluid = TouchDynamicsConfiguration(
        illumination: .init(intensity: 0.16, radius: 110, falloff: 0.45, rampInDuration: 0.09),
        ripple: .init(duration: 0.38, profile: .combined, wavefrontWidth: 28, decay: 2.4),
        elasticity: .init(strength: 0.025, mode: .anchoredScale, tension: 0.06, damping: 0.72, stiffness: 320)
    )

    /// Stronger spring and touch deformation.
    static let elastic = TouchDynamicsConfiguration(
        illumination: .init(intensity: 0.14, radius: 120, falloff: 0.5),
        ripple: .init(duration: 0.42, profile: .combined, wavefrontWidth: 34, decay: 2.0),
        elasticity: .init(strength: 0.045, mode: .anchoredScale, tension: 0.12, maximumDeformation: 0.1, damping: 0.5, stiffness: 260)
    )

    /// Soft, diffused, surface-oriented feedback. The illumination stays where
    /// the touch began, and a drag or a scroll dissipates it, like a material
    /// surface.
    static let material = TouchDynamicsConfiguration(
        illumination: .init(intensity: 0.12, radius: 160, falloff: 0.7, rampInDuration: 0.12, tracking: .anchored),
        ripple: .init(duration: 0.45, profile: .softGradient, decay: 1.8, origin: .initialLocation),
        elasticity: .init(strength: 0.008, mode: .uniformScale, tension: 0, damping: 0.9, stiffness: 400),
        gesture: .init(dragBehavior: .dissipate, scrollTakeover: .dissipate)
    )

    /// Illumination and wave without any deformation.
    static let rippleOnly = TouchDynamicsConfiguration(
        illumination: .init(intensity: 0.16, radius: 110),
        ripple: .init(duration: 0.38, profile: .combined),
        elasticity: .off
    )
}
