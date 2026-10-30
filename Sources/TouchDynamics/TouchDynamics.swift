import Foundation

/// The TouchDynamics SDK namespace.
///
/// TouchDynamics adds physically responsive touch feedback — illumination under
/// the finger, a release ripple, and a damped elastic deformation — to any
/// UIKit or SwiftUI view without replacing the host application's gestures.
///
/// - SwiftUI: apply `.touchDynamics()` to any view.
/// - UIKit: call ``TouchDynamics/attach(to:configuration:)``.
///
/// The engine (``TouchInteractionEngine``) and the physics models
/// (``SpringSolver``, ``RippleWave``, ``IlluminationField``,
/// ``DeformationField``) are public so advanced integrations can drive custom
/// renderers from the same deterministic state machine.
public enum TouchDynamics {
    /// The SDK version, following semantic versioning.
    public static let version = "1.2.3"
}
