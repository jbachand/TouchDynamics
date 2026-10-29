import Foundation
import CoreGraphics

/// The release wave `R(r, t) = B·e^(−λt) · exp(−(r − vt)² / 2w²)`.
///
/// The wavefront position is eased rather than linear so the wave decelerates
/// as it dissipates; `travelRadius` is where the front has fully left the
/// surface. Both renderers sample this model, so the Core Animation keyframes
/// and the Metal shader produce the same picture.
public struct RippleWave: Sendable, Equatable {
    /// Distance from the origin to the farthest point that must be covered.
    public var coverageRadius: CGFloat
    /// Gaussian half-width of the wavefront, in points.
    public var wavefrontWidth: CGFloat
    /// Total duration in seconds.
    public var duration: TimeInterval
    /// Opacity decay rate over normalized time.
    public var decay: Double
    /// Peak opacity `B`.
    public var peakIntensity: CGFloat
    public var profile: RippleProfile

    public init(
        coverageRadius: CGFloat,
        wavefrontWidth: CGFloat,
        duration: TimeInterval,
        decay: Double,
        peakIntensity: CGFloat,
        profile: RippleProfile = .combined
    ) {
        self.coverageRadius = max(1, coverageRadius)
        self.wavefrontWidth = max(1, wavefrontWidth)
        self.duration = max(0.05, duration)
        self.decay = max(0.1, decay)
        self.peakIntensity = peakIntensity.clamped(to: 0...1)
        self.profile = profile
    }

    /// Distance from `origin` to the farthest corner of `bounds`.
    public static func coverageRadius(from origin: CGPoint, in bounds: CGRect) -> CGFloat {
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        return corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? 0
    }

    /// Radius the front must reach for the ring to be fully outside the surface.
    public var travelRadius: CGFloat { coverageRadius + 2 * wavefrontWidth }

    /// Average front speed `v` in points per second.
    public var speed: CGFloat { travelRadius / CGFloat(duration) }

    /// Normalized time `0...1`.
    public func progress(at t: TimeInterval) -> Double {
        (t / duration).clamped(to: 0...1)
    }

    /// Wavefront radius at time `t` (quadratic ease-out).
    public func radius(at t: TimeInterval) -> CGFloat {
        let p = progress(at: t)
        let eased = 1 - (1 - p) * (1 - p)
        return travelRadius * CGFloat(eased)
    }

    /// Opacity envelope at time `t`: `e^(−λp)` renormalized to run from 1 to 0.
    public func envelope(at t: TimeInterval) -> CGFloat {
        let p = progress(at: t)
        let e = exp(-decay * p)
        let end = exp(-decay)
        return CGFloat((e - end) / (1 - end)).clamped(to: 0...1)
    }

    /// Opacity of the wavefront ring at distance `r` and time `t`.
    public func ringIntensity(atDistance r: CGFloat, time t: TimeInterval) -> CGFloat {
        let d = r - radius(at: t)
        let w = wavefrontWidth
        return peakIntensity * envelope(at: t) * exp(-(d * d) / (2 * w * w))
    }

    /// Opacity of the soft disc behind the front at distance `r` and time `t`.
    public func discIntensity(atDistance r: CGFloat, time t: TimeInterval) -> CGFloat {
        let front = radius(at: t)
        let inner = front - wavefrontWidth
        let s: CGFloat
        if r <= inner {
            s = 1
        } else if r >= front {
            s = 0
        } else {
            let u = (r - inner) / max(1e-6, front - inner)
            s = 1 - (u * u * (3 - 2 * u))
        }
        return 0.6 * peakIntensity * envelope(at: t) * s
    }

    /// Combined opacity according to ``profile``.
    public func intensity(atDistance r: CGFloat, time t: TimeInterval) -> CGFloat {
        switch profile {
        case .softGradient:
            return discIntensity(atDistance: r, time: t)
        case .wavefront:
            return ringIntensity(atDistance: r, time: t)
        case .combined:
            return min(1, discIntensity(atDistance: r, time: t) + ringIntensity(atDistance: r, time: t))
        }
    }

    /// `count` evenly spaced sample times from 0 to `duration`.
    public func sampleTimes(count: Int = 30) -> [TimeInterval] {
        let n = max(2, count)
        return (0..<n).map { duration * Double($0) / Double(n - 1) }
    }
}
