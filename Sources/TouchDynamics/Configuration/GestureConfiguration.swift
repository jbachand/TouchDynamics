import Foundation
import CoreGraphics

/// What happens when the finger moves beyond the tap slop without an ancestor
/// scroll view claiming the gesture.
public enum DragBehavior: Sendable, Equatable {
    /// Keep illuminating and track the finger (directional tension applies).
    case follow
    /// Treat the drag as a cancellation and dissipate the effect.
    case dissipate
}

/// What happens when the finger lifts after a drag that stayed inside bounds.
public enum ReleaseBehavior: Sendable, Equatable {
    /// Emit the release ripple.
    case ripple
    /// Fade out without a ripple.
    case dissipate
}

/// How an effect is removed when the gesture is cancelled or a scroll takes over.
public enum CancellationBehavior: Sendable, Equatable {
    /// A short fade and spring back.
    case dissipate
    /// Immediate removal with no animation.
    case suppress
}

/// Configuration for touch interpretation and gesture arbitration.
///
/// TouchDynamics never claims touches. It observes them with a gesture
/// recognizer that cannot prevent, and cannot be prevented by, any other
/// recognizer, and it watches ancestor scroll views' pan recognizers to learn
/// when a scroll has taken over.
public struct GestureConfiguration: Sendable, Equatable {
    /// Movement in points allowed before a press is considered a drag.
    public var tapSlop: CGFloat
    /// Time after which a steady press is reported as a long press.
    public var longPressDuration: TimeInterval
    /// Behavior when the finger drags without a scroll taking over.
    public var dragBehavior: DragBehavior
    /// Behavior when the finger lifts after a drag inside the bounds.
    public var releaseAfterDrag: ReleaseBehavior
    /// Behavior when an ancestor scroll view starts scrolling.
    public var scrollTakeover: CancellationBehavior
    /// How far the surface itself may move on screen while a finger is down
    /// before the movement is treated as a scroll. This catches containers
    /// that are not `UIScrollView`-backed; `UIScrollView` pans are observed
    /// directly as well.
    public var scrollDetectionDistance: CGFloat
    /// Behavior when the system cancels the touch.
    public var cancellation: CancellationBehavior
    /// Distance outside the bounds the finger may travel while still counting
    /// as inside, mirroring `UIControl` touch-up-inside tolerance.
    public var exitMargin: CGFloat
    /// Upper bound on simultaneous effect sessions; extra touches are ignored.
    public var maximumConcurrentTouches: Int
    /// Whether trackpad/mouse clicks (indirect pointer touches) trigger effects.
    public var acceptsIndirectPointer: Bool

    public init(
        tapSlop: CGFloat = 10,
        longPressDuration: TimeInterval = 0.5,
        dragBehavior: DragBehavior = .follow,
        releaseAfterDrag: ReleaseBehavior = .ripple,
        scrollTakeover: CancellationBehavior = .dissipate,
        scrollDetectionDistance: CGFloat = 4,
        cancellation: CancellationBehavior = .dissipate,
        exitMargin: CGFloat = 40,
        maximumConcurrentTouches: Int = 5,
        acceptsIndirectPointer: Bool = true
    ) {
        self.tapSlop = max(0, tapSlop)
        self.longPressDuration = max(0.05, longPressDuration)
        self.dragBehavior = dragBehavior
        self.releaseAfterDrag = releaseAfterDrag
        self.scrollTakeover = scrollTakeover
        self.scrollDetectionDistance = max(0, scrollDetectionDistance)
        self.cancellation = cancellation
        self.exitMargin = max(0, exitMargin)
        self.maximumConcurrentTouches = max(1, maximumConcurrentTouches)
        self.acceptsIndirectPointer = acceptsIndirectPointer
    }
}
