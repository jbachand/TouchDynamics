import Foundation
import CoreGraphics

/// A raw touch event fed into ``TouchInteractionEngine``.
///
/// Locations are in the surface's coordinate space; times are monotonic
/// (`UITouch.timestamp` is compatible).
public enum TouchEvent: Sendable, Equatable {
    case began(id: TouchIdentifier, location: CGPoint, time: TimeInterval)
    case moved(id: TouchIdentifier, location: CGPoint, time: TimeInterval)
    case ended(id: TouchIdentifier, location: CGPoint, time: TimeInterval)
    case cancelled(id: TouchIdentifier, time: TimeInterval)

    public var id: TouchIdentifier {
        switch self {
        case .began(let id, _, _), .moved(let id, _, _), .ended(let id, _, _), .cancelled(let id, _):
            return id
        }
    }

    public var time: TimeInterval {
        switch self {
        case .began(_, _, let t), .moved(_, _, let t), .ended(_, _, let t), .cancelled(_, let t):
            return t
        }
    }
}

/// A rendering instruction emitted by ``TouchInteractionEngine``.
///
/// Renderers are stateless with respect to gesture logic: they only react to
/// commands, which keeps UIKit, SwiftUI, Core Animation and Metal on one
/// deterministic state machine.
public enum EngineCommand: Sendable, Equatable {
    /// A touch began inside the surface: ramp the illumination in and apply
    /// the press deformation at `session.startLocation`.
    case illuminate(TouchSession)
    /// The finger moved: update illumination position and directional tension.
    case track(TouchSession)
    /// The press has lasted the long-press duration: deepen the feedback.
    case longPress(TouchSession)
    /// The finger lifted inside the surface. Emit the ripple when `ripple` is
    /// true and spring the deformation back.
    case release(TouchSession, ripple: Bool)
    /// Cancelled, dragged away, or a scroll took over: fade out and spring back.
    /// `immediate` requests removal without animation.
    case dissipate(TouchSession, immediate: Bool)
    /// Remove every effect now (cell reuse, detach).
    case reset
}
