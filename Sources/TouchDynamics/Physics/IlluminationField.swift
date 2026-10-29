import Foundation
import CoreGraphics

/// The radial illumination model `I(r) = A · exp(−r² / 2σ²)`, windowed to zero
/// at ``radius`` so the field has a definite visible edge.
public struct IlluminationField: Sendable, Equatable {
    /// Visible radius in points.
    public var radius: CGFloat
    /// `σ / radius`.
    public var falloff: CGFloat
    /// Peak opacity `A`.
    public var intensity: CGFloat

    public init(radius: CGFloat, falloff: CGFloat, intensity: CGFloat) {
        self.radius = max(1, radius)
        self.falloff = falloff.clamped(to: 0.05...1)
        self.intensity = intensity.clamped(to: 0...1)
    }

    public init(configuration: IlluminationConfiguration) {
        self.init(radius: configuration.radius, falloff: configuration.falloff, intensity: configuration.intensity)
    }

    /// σ in points.
    public var sigma: CGFloat { radius * falloff }

    /// Opacity at distance `r` from the touch point.
    public func intensity(atDistance r: CGFloat) -> CGFloat {
        guard r < radius, r >= 0 else { return 0 }
        let s = sigma
        let gaussian = exp(-(r * r) / (2 * s * s))
        let u = r / radius
        let window = 1 - u * u * u * u
        return intensity * gaussian * window
    }

    /// Gradient stops from the center (`location` 0) to the edge (`location` 1).
    /// `alpha` is the absolute opacity at that stop.
    public func gradientStops(count: Int = 10) -> [(location: CGFloat, alpha: CGFloat)] {
        let n = max(2, count)
        return (0..<n).map { i in
            let location = CGFloat(i) / CGFloat(n - 1)
            let alpha = i == n - 1 ? 0 : intensity(atDistance: location * radius)
            return (location: location, alpha: alpha)
        }
    }
}
