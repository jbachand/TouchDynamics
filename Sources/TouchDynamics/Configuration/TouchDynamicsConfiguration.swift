import Foundation
import CoreGraphics

/// The complete configuration for a TouchDynamics surface.
///
/// Start from a preset and override what you need:
///
/// ```swift
/// var config = TouchDynamicsConfiguration.fluid
/// config.illumination.radius = 90
/// config.ripple.duration = 0.3
/// ```
///
/// Every property has a documented default, and new properties will be added
/// with defaults so existing call sites keep compiling.
public struct TouchDynamicsConfiguration: Sendable, Equatable {
    /// Illumination under the finger.
    public var illumination: IlluminationConfiguration
    /// Release wave.
    public var ripple: RippleConfiguration
    /// Elastic deformation.
    public var elasticity: ElasticityConfiguration
    /// Touch interpretation and gesture arbitration.
    public var gesture: GestureConfiguration
    /// Renderer and clipping.
    public var rendering: RenderingConfiguration
    /// Accessibility adaptations.
    public var accessibility: AccessibilityConfiguration

    public init(
        illumination: IlluminationConfiguration = .init(),
        ripple: RippleConfiguration = .init(),
        elasticity: ElasticityConfiguration = .init(),
        gesture: GestureConfiguration = .init(),
        rendering: RenderingConfiguration = .init(),
        accessibility: AccessibilityConfiguration = .init()
    ) {
        self.illumination = illumination
        self.ripple = ripple
        self.elasticity = elasticity
        self.gesture = gesture
        self.rendering = rendering
        self.accessibility = accessibility
    }

    /// Builds a fully custom configuration. Equivalent to the initializer; it
    /// exists so call sites can read `.custom(...)` alongside the presets.
    public static func custom(
        illumination: IlluminationConfiguration = .init(),
        ripple: RippleConfiguration = .init(),
        elasticity: ElasticityConfiguration = .init(),
        gesture: GestureConfiguration = .init(),
        rendering: RenderingConfiguration = .init(),
        accessibility: AccessibilityConfiguration = .init()
    ) -> TouchDynamicsConfiguration {
        .init(
            illumination: illumination,
            ripple: ripple,
            elasticity: elasticity,
            gesture: gesture,
            rendering: rendering,
            accessibility: accessibility
        )
    }
}
