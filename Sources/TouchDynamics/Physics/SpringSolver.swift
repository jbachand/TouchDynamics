import Foundation

/// Closed-form solution of the damped harmonic oscillator
/// `m·ẍ + c·ẋ + k·x = 0`, parameterized by mass, stiffness and damping ratio.
///
/// Every renderer derives its spring timing from this type, so Core Animation,
/// Metal and SwiftUI settle on the same curve. `UISpringTimingParameters`,
/// `CASpringAnimation` and SwiftUI's `interpolatingSpring` take the same
/// `(mass, stiffness, damping)` triple; use ``dampingCoefficient`` for the
/// third value.
public struct SpringSolver: Sendable, Equatable {
    public var mass: Double
    public var stiffness: Double
    /// ζ. `< 1` underdamped (overshoots), `1` critical, `> 1` overdamped.
    public var dampingRatio: Double

    public init(mass: Double = 1, stiffness: Double = 320, dampingRatio: Double = 0.72) {
        self.mass = max(1e-6, mass)
        self.stiffness = max(1e-6, stiffness)
        self.dampingRatio = max(1e-4, dampingRatio)
    }

    /// ω₀ = √(k / m).
    public var undampedAngularFrequency: Double { (stiffness / mass).squareRoot() }

    /// `c = 2ζ√(km)`, the value UIKit, Core Animation and SwiftUI call `damping`.
    public var dampingCoefficient: Double { 2 * dampingRatio * (stiffness * mass).squareRoot() }

    /// Displacement from rest at time `t` for an initial displacement `x0` and
    /// initial velocity `v0`.
    public func displacement(at t: TimeInterval, initialDisplacement x0: Double, initialVelocity v0: Double = 0) -> Double {
        guard t > 0 else { return x0 }
        let w0 = undampedAngularFrequency
        let z = dampingRatio
        if abs(z - 1) < 1e-6 {
            // Critically damped.
            let c1 = x0
            let c2 = v0 + w0 * x0
            return (c1 + c2 * t) * exp(-w0 * t)
        } else if z < 1 {
            // Underdamped.
            let wd = w0 * (1 - z * z).squareRoot()
            let c1 = x0
            let c2 = (v0 + z * w0 * x0) / wd
            return exp(-z * w0 * t) * (c1 * cos(wd * t) + c2 * sin(wd * t))
        } else {
            // Overdamped.
            let s = w0 * (z * z - 1).squareRoot()
            let r1 = -z * w0 + s
            let r2 = -z * w0 - s
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            return c1 * exp(r1 * t) + c2 * exp(r2 * t)
        }
    }

    /// Value at time `t` moving from `start` to `target`.
    public func value(at t: TimeInterval, from start: Double, to target: Double, initialVelocity v0: Double = 0) -> Double {
        target + displacement(at: t, initialDisplacement: start - target, initialVelocity: v0)
    }

    /// Time until the response stays within `tolerance` of rest, for a unit
    /// initial displacement unless specified. Sampled at 240 Hz, capped at 5 s.
    public func settlingDuration(
        initialDisplacement x0: Double = 1,
        initialVelocity v0: Double = 0,
        tolerance: Double = 0.001
    ) -> TimeInterval {
        let tol = max(1e-9, abs(tolerance))
        guard abs(x0) > tol || abs(v0) > tol else { return 0 }
        let step = 1.0 / 240.0
        let cap = 5.0
        var lastOutside = 0.0
        var t = 0.0
        while t <= cap {
            if abs(displacement(at: t, initialDisplacement: x0, initialVelocity: v0)) >= tol {
                lastOutside = t
            }
            t += step
        }
        return min(cap, lastOutside + step)
    }
}
