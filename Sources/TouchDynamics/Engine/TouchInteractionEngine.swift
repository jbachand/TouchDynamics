import Foundation
import CoreGraphics

/// The deterministic touch state machine at the center of TouchDynamics.
///
/// Feed it ``TouchEvent``s, scroll notifications and renderer completions; it
/// emits ``EngineCommand``s through ``onCommand``. It holds one
/// ``TouchSession`` per finger, bounded by
/// ``GestureConfiguration/maximumConcurrentTouches``.
///
/// Aggregate state: `idle → pressing → tracking → releasing → settling → idle`,
/// with `scrolling` and `detached` as alternates. The engine has no timers of
/// its own; hosts call ``tick(now:)`` for long-press promotion and for pruning
/// sessions whose renderer never reported completion.
@MainActor
public final class TouchInteractionEngine {
    /// Gesture arbitration parameters. Changes apply to subsequent events.
    public var configuration: GestureConfiguration
    /// The surface bounds, in the same coordinate space as event locations.
    /// Used for inside/outside decisions. An empty rect disables the check.
    public var bounds: CGRect
    /// Sessions in a finishing phase are pruned after this long if the renderer
    /// never calls ``effectDidSettle(_:)``.
    public var settleTimeout: TimeInterval = 2.0
    /// Receives commands synchronously as events are processed.
    public var onCommand: ((EngineCommand) -> Void)?

    public private(set) var state: TouchEngineState = .idle
    /// True between ``scrollDidBegin(at:)`` and ``scrollDidEnd(at:)``.
    public private(set) var isScrolling = false

    private var order: [TouchIdentifier] = []
    private var storage: [TouchIdentifier: TouchSession] = [:]
    private var finishTimes: [TouchIdentifier: TimeInterval] = [:]
    private let clock: any TouchDynamicsClock

    public init(
        configuration: GestureConfiguration = .init(),
        bounds: CGRect = .zero,
        clock: any TouchDynamicsClock = MonotonicClock()
    ) {
        self.configuration = configuration
        self.bounds = bounds
        self.clock = clock
    }

    // MARK: Introspection

    /// All sessions in creation order.
    public var sessions: [TouchSession] { order.compactMap { storage[$0] } }
    /// Sessions whose finger is still down.
    public var activeSessions: [TouchSession] { sessions.filter { $0.phase.isActive } }
    public var isIdle: Bool { state == .idle }

    public func session(for id: TouchIdentifier) -> TouchSession? { storage[id] }

    // MARK: Events

    public func handle(_ event: TouchEvent) {
        guard state != .detached else { return }
        switch event {
        case .began(let id, let location, let time):
            began(id: id, location: location, time: time)
        case .moved(let id, let location, let time):
            moved(id: id, location: location, time: time)
        case .ended(let id, let location, let time):
            ended(id: id, location: location, time: time)
        case .cancelled(let id, let time):
            cancelled(id: id, time: time)
        }
        updateAggregateState()
    }

    /// An ancestor scroll view started scrolling.
    ///
    /// Under ``ScrollTakeoverBehavior/maintain`` active sessions keep their
    /// phase and are flagged ``TouchSession/didScroll``. Otherwise they
    /// dissipate and move to ``TouchPhase/scrolling``, and new touches during
    /// the scroll show nothing, like a native highlight.
    public func scrollDidBegin(at time: TimeInterval? = nil) {
        guard state != .detached else { return }
        isScrolling = true
        let now = time ?? clock.now()
        for id in order {
            guard var s = storage[id], s.phase == .pressing || s.phase == .tracking else { continue }
            s.elapsedTime = now - s.startTime
            s.didScroll = true
            switch configuration.scrollTakeover {
            case .maintain:
                storage[id] = s
            case .dissipate:
                s.phase = .scrolling
                storage[id] = s
                emit(.dissipate(s, immediate: false))
            case .suppress:
                s.phase = .scrolling
                storage[id] = s
                emit(.dissipate(s, immediate: true))
            }
        }
        updateAggregateState()
    }

    /// The scroll ended (or failed).
    public func scrollDidEnd(at time: TimeInterval? = nil) {
        isScrolling = false
        updateAggregateState()
    }

    /// The renderer finished the ripple for `id`; the spring may still settle.
    public func rippleDidFinish(_ id: TouchIdentifier) {
        guard var s = storage[id], s.phase == .releasing else { return }
        s.phase = .settling
        storage[id] = s
        updateAggregateState()
    }

    /// The renderer finished every exit animation for `id`.
    public func effectDidSettle(_ id: TouchIdentifier) {
        guard let s = storage[id] else { return }
        if s.phase.isFinishing {
            remove(id)
        }
        updateAggregateState()
    }

    /// Promotes long presses and prunes stale sessions. Call from a timer or
    /// display callback; the engine never schedules anything itself.
    public func tick(now: TimeInterval? = nil) {
        guard state != .detached else { return }
        let now = now ?? clock.now()
        for id in order {
            guard var s = storage[id] else { continue }
            if s.phase == .pressing, !s.isLongPress, now - s.startTime >= configuration.longPressDuration {
                s.isLongPress = true
                s.elapsedTime = now - s.startTime
                storage[id] = s
                emit(.longPress(s))
            }
            if s.phase.isFinishing, let finished = finishTimes[id], now - finished > settleTimeout {
                remove(id)
            }
        }
        updateAggregateState()
    }

    /// Drops every session and asks the renderer to clear. Use for cell reuse.
    public func reset() {
        order.removeAll()
        storage.removeAll()
        finishTimes.removeAll()
        isScrolling = false
        emit(.reset)
        if state != .detached { state = .idle }
    }

    /// Resets and permanently stops processing events.
    public func detach() {
        reset()
        state = .detached
    }

    // MARK: Transitions

    private func began(id: TouchIdentifier, location: CGPoint, time: TimeInterval) {
        guard storage[id] == nil else { return }
        let activeCount = storage.values.reduce(0) { $0 + ($1.phase.isActive ? 1 : 0) }
        guard activeCount < configuration.maximumConcurrentTouches else { return }
        if isScrolling, activeCount == 0 {
            // A scroll needs a finger. With none tracked, the end notification
            // was missed (it can race the last touch-up); do not stay dark.
            isScrolling = false
        }

        var session = TouchSession(
            id: id,
            startLocation: location,
            startTime: time,
            isInsideBounds: containsWithMargin(location)
        )
        if isScrolling {
            session.didScroll = true
            if configuration.scrollTakeover != .maintain {
                session.phase = .scrolling
                insert(session)
                return
            }
        }
        session.phase = .pressing
        insert(session)
        emit(.illuminate(session))
    }

    private func moved(id: TouchIdentifier, location: CGPoint, time: TimeInterval) {
        guard var s = storage[id] else { return }
        let dt = time - s.lastUpdateTime
        if dt > 0 {
            let instantaneous = CGVector(
                dx: (location.x - s.currentLocation.x) / dt,
                dy: (location.y - s.currentLocation.y) / dt
            )
            s.velocity = CGVector(
                dx: 0.6 * instantaneous.dx + 0.4 * s.velocity.dx,
                dy: 0.6 * instantaneous.dy + 0.4 * s.velocity.dy
            )
        }
        s.currentLocation = location
        s.lastUpdateTime = time
        s.elapsedTime = time - s.startTime
        s.isInsideBounds = containsWithMargin(location)

        switch s.phase {
        case .pressing:
            if s.distanceFromStart > configuration.tapSlop {
                switch configuration.dragBehavior {
                case .follow:
                    s.phase = .tracking
                    storage[id] = s
                    emit(.track(s))
                case .dissipate:
                    s.phase = .cancelled
                    finishTimes[id] = time
                    storage[id] = s
                    emit(.dissipate(s, immediate: false))
                }
            } else {
                storage[id] = s
                emit(.track(s))
            }
        case .tracking:
            storage[id] = s
            emit(.track(s))
        case .scrolling, .releasing, .settling, .cancelled:
            storage[id] = s
        }
    }

    private func ended(id: TouchIdentifier, location: CGPoint, time: TimeInterval) {
        guard var s = storage[id] else { return }
        s.currentLocation = location
        s.lastUpdateTime = time
        s.elapsedTime = time - s.startTime
        s.isInsideBounds = containsWithMargin(location)
        s.releaseLocation = location

        switch s.phase {
        case .pressing, .tracking:
            if s.isInsideBounds {
                let ripple: Bool
                if s.didScroll {
                    ripple = configuration.releaseAfterScroll == .ripple
                } else {
                    ripple = s.phase == .pressing || configuration.releaseAfterDrag == .ripple
                }
                s.phase = .releasing
                finishTimes[id] = time
                storage[id] = s
                emit(.release(s, ripple: ripple))
            } else {
                s.phase = .cancelled
                finishTimes[id] = time
                storage[id] = s
                emit(.dissipate(s, immediate: false))
            }
        case .scrolling:
            remove(id)
        case .cancelled, .releasing, .settling:
            storage[id] = s
        }
    }

    private func cancelled(id: TouchIdentifier, time: TimeInterval) {
        guard var s = storage[id] else { return }
        s.lastUpdateTime = time
        s.elapsedTime = time - s.startTime
        switch s.phase {
        case .pressing, .tracking:
            s.phase = .cancelled
            finishTimes[id] = time
            storage[id] = s
            emit(.dissipate(s, immediate: configuration.cancellation == .suppress))
        case .scrolling:
            remove(id)
        case .cancelled, .releasing, .settling:
            storage[id] = s
        }
    }

    // MARK: Helpers

    private func insert(_ session: TouchSession) {
        order.append(session.id)
        storage[session.id] = session
    }

    private func remove(_ id: TouchIdentifier) {
        storage[id] = nil
        finishTimes[id] = nil
        order.removeAll { $0 == id }
    }

    private func containsWithMargin(_ point: CGPoint) -> Bool {
        guard !bounds.isEmpty else { return true }
        return bounds.insetBy(dx: -configuration.exitMargin, dy: -configuration.exitMargin).contains(point)
    }

    private func emit(_ command: EngineCommand) {
        onCommand?(command)
    }

    private func updateAggregateState() {
        guard state != .detached else { return }
        var phases = Set<TouchPhase>()
        for s in storage.values { phases.insert(s.phase) }
        if phases.contains(.tracking) {
            state = .tracking
        } else if phases.contains(.pressing) {
            state = .pressing
        } else if phases.contains(.scrolling) {
            state = .scrolling
        } else if phases.contains(.releasing) {
            state = .releasing
        } else if phases.contains(.settling) || phases.contains(.cancelled) {
            state = .settling
        } else {
            state = .idle
        }
    }
}
