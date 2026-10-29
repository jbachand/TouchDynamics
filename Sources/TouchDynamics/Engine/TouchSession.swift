import Foundation
import CoreGraphics

/// The per-touch phase of the interaction state machine.
///
/// A touch moves `pressing → tracking → releasing → settling` and is then
/// removed. `scrolling` and `cancelled` are the alternate exits.
public enum TouchPhase: String, Sendable, Hashable, CaseIterable {
    /// Finger down, within the tap slop. Illumination is on.
    case pressing
    /// Finger moving beyond the tap slop, not claimed by a scroll view.
    case tracking
    /// Finger lifted; the ripple is running.
    case releasing
    /// Ripple done; the spring is still settling.
    case settling
    /// Cancelled by the system or by a drag; the effect is dissipating.
    case cancelled
    /// An ancestor scroll view took the gesture and the effect was dropped
    /// (``ScrollTakeoverBehavior/dissipate`` or ``ScrollTakeoverBehavior/suppress``);
    /// nothing further is shown. Under ``ScrollTakeoverBehavior/maintain`` the
    /// session keeps its phase and ``TouchSession/didScroll`` is set instead.
    case scrolling

    /// The finger is still on the screen.
    public var isActive: Bool {
        switch self {
        case .pressing, .tracking, .scrolling: return true
        case .releasing, .settling, .cancelled: return false
        }
    }

    /// The finger has lifted and an exit animation may be running.
    public var isFinishing: Bool {
        switch self {
        case .releasing, .settling, .cancelled: return true
        case .pressing, .tracking, .scrolling: return false
        }
    }
}

/// The aggregate state of a ``TouchInteractionEngine``.
public enum TouchEngineState: String, Sendable, Hashable {
    case idle
    case pressing
    case tracking
    case releasing
    case settling
    case scrolling
    case detached
}

/// One touch, from touch-down through settle.
///
/// Locations are in the attached surface's coordinate space (origin at the
/// top-left of its bounds). Times come from the engine's monotonic clock.
public struct TouchSession: Sendable, Equatable {
    public let id: TouchIdentifier
    public let startLocation: CGPoint
    public let startTime: TimeInterval
    public var currentLocation: CGPoint
    /// Smoothed finger velocity in points per second.
    public var velocity: CGVector
    public var phase: TouchPhase
    public var elapsedTime: TimeInterval
    public var lastUpdateTime: TimeInterval
    /// Whether the finger is within the bounds plus the configured exit margin.
    public var isInsideBounds: Bool
    /// Set once the press has lasted ``GestureConfiguration/longPressDuration``.
    public var isLongPress: Bool
    /// Set when the content scrolled while this finger was down.
    public var didScroll: Bool
    /// Where the finger lifted, once it has.
    public var releaseLocation: CGPoint?

    public init(
        id: TouchIdentifier,
        startLocation: CGPoint,
        startTime: TimeInterval,
        phase: TouchPhase = .pressing,
        isInsideBounds: Bool = true
    ) {
        self.id = id
        self.startLocation = startLocation
        self.startTime = startTime
        self.currentLocation = startLocation
        self.velocity = .zero
        self.phase = phase
        self.elapsedTime = 0
        self.lastUpdateTime = startTime
        self.isInsideBounds = isInsideBounds
        self.isLongPress = false
        self.didScroll = false
        self.releaseLocation = nil
    }

    /// Finger displacement from the start location.
    public var displacement: CGVector {
        CGVector(dx: currentLocation.x - startLocation.x, dy: currentLocation.y - startLocation.y)
    }

    /// Distance travelled from the start location.
    public var distanceFromStart: CGFloat {
        let d = displacement
        return (d.dx * d.dx + d.dy * d.dy).squareRoot()
    }

    public static func == (lhs: TouchSession, rhs: TouchSession) -> Bool {
        lhs.id == rhs.id
            && lhs.startLocation == rhs.startLocation
            && lhs.startTime == rhs.startTime
            && lhs.currentLocation == rhs.currentLocation
            && lhs.velocity.dx == rhs.velocity.dx
            && lhs.velocity.dy == rhs.velocity.dy
            && lhs.phase == rhs.phase
            && lhs.elapsedTime == rhs.elapsedTime
            && lhs.lastUpdateTime == rhs.lastUpdateTime
            && lhs.isInsideBounds == rhs.isInsideBounds
            && lhs.isLongPress == rhs.isLongPress
            && lhs.didScroll == rhs.didScroll
            && lhs.releaseLocation == rhs.releaseLocation
    }
}
