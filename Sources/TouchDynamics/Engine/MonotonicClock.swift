import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

/// A monotonic time source used for all animation timing.
///
/// The engine never counts frames; it reads a clock. Tests inject a manual
/// clock to drive the state machine deterministically.
public protocol TouchDynamicsClock: Sendable {
    /// Seconds from an arbitrary fixed origin. Never decreases.
    func now() -> TimeInterval
}

/// The system monotonic clock, shared with `UITouch.timestamp` and
/// `CACurrentMediaTime()` (both are `mach_absolute_time`-based).
public struct MonotonicClock: TouchDynamicsClock {
    public init() {}

    public func now() -> TimeInterval {
        #if canImport(QuartzCore)
        return CACurrentMediaTime()
        #else
        return ProcessInfo.processInfo.systemUptime
        #endif
    }
}
