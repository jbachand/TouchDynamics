import Foundation
import CoreGraphics

/// The animation used to move between deformation states.
public enum DeformationAnimation: Sendable, Equatable {
    /// Jump immediately.
    case none
    /// Ease out over a duration (press-in, finger tracking).
    case easeOut(duration: TimeInterval)
    /// Damped spring (release).
    case spring(SpringSolver)
}

/// A layout-neutral affine deformation of a surface.
///
/// `anchor` is in the surface's bounds coordinate space (origin top-left).
/// `scaleX/scaleY` scale about the anchor; `shearX/shearY` are affine shear
/// factors; `translation` is applied last.
public struct DeformationState: Sendable, Equatable {
    public var scaleX: CGFloat
    public var scaleY: CGFloat
    public var shearX: CGFloat
    public var shearY: CGFloat
    public var translation: CGVector
    public var anchor: CGPoint

    public init(
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1,
        shearX: CGFloat = 0,
        shearY: CGFloat = 0,
        translation: CGVector = .zero,
        anchor: CGPoint = .zero
    ) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.shearX = shearX
        self.shearY = shearY
        self.translation = translation
        self.anchor = anchor
    }

    /// No deformation, anchored at the origin.
    public static let identity = DeformationState()

    /// No deformation, keeping `anchor` so interpolation toward rest does not
    /// drift the pivot.
    public static func identity(anchor: CGPoint) -> DeformationState {
        DeformationState(anchor: anchor)
    }

    /// Whether the state has no visible effect.
    public var isIdentity: Bool {
        abs(scaleX - 1) < 1e-6 && abs(scaleY - 1) < 1e-6
            && abs(shearX) < 1e-6 && abs(shearY) < 1e-6
            && abs(translation.dx) < 1e-6 && abs(translation.dy) < 1e-6
    }

    /// Coordinate convention for ``affineTransform(in:origin:)``.
    public enum TransformOrigin: Sendable {
        /// The transform acts on bounds coordinates (SwiftUI `GeometryEffect`).
        case topLeft
        /// The transform acts about the bounds center (`UIView.transform`).
        case center
    }

    /// The affine transform realizing this state for a surface of `bounds`.
    ///
    /// `p' = a + S·(p − a) + t`, where `S = [sx, shx; shy, sy]`, expressed in
    /// the requested coordinate convention.
    public func affineTransform(in bounds: CGRect, origin: TransformOrigin) -> CGAffineTransform {
        let pivot: CGPoint
        switch origin {
        case .topLeft:
            pivot = CGPoint(x: anchor.x - bounds.minX, y: anchor.y - bounds.minY)
        case .center:
            pivot = CGPoint(x: anchor.x - bounds.midX, y: anchor.y - bounds.midY)
        }
        // S applied to the pivot.
        let sx = scaleX * pivot.x + shearX * pivot.y
        let sy = shearY * pivot.x + scaleY * pivot.y
        let tx = pivot.x - sx + translation.dx
        let ty = pivot.y - sy + translation.dy
        return CGAffineTransform(a: scaleX, b: shearY, c: shearX, d: scaleY, tx: tx, ty: ty)
    }
}

/// Derives ``DeformationState``s from touch sessions according to an
/// ``ElasticityConfiguration``.
public struct DeformationField: Sendable, Equatable {
    public var configuration: ElasticityConfiguration

    public init(configuration: ElasticityConfiguration) {
        self.configuration = configuration
    }

    /// The deformation for a finger currently on the surface.
    /// - Parameters:
    ///   - session: the touch.
    ///   - bounds: the surface bounds.
    ///   - emphasis: multiplier applied to the press strength (long press uses > 1).
    public func state(for session: TouchSession, in bounds: CGRect, emphasis: CGFloat = 1) -> DeformationState {
        guard configuration.isEnabled, !bounds.isEmpty else {
            return .identity(anchor: session.startLocation)
        }
        let cfg = configuration
        let limit = cfg.maximumDeformation
        let press = min(limit, cfg.strength * max(0, emphasis))
        let base: CGFloat = cfg.response == .compress ? 1 - press : 1 + press

        let width = max(1, bounds.width)
        let height = max(1, bounds.height)
        let d = session.displacement
        // Fraction of the surface the finger has travelled, per axis.
        let fx = (abs(d.dx) / width).clamped(to: 0...1)
        let fy = (abs(d.dy) / height).clamped(to: 0...1)

        var state = DeformationState()
        switch cfg.mode {
        case .uniformScale:
            state.anchor = CGPoint(x: bounds.midX, y: bounds.midY)
            state.scaleX = base
            state.scaleY = base
            state.scaleX = clampScale(state.scaleX + cfg.tension * fx, limit: limit)
            state.scaleY = clampScale(state.scaleY + cfg.tension * fy, limit: limit)

        case .anchoredScale, .displacement:
            state.anchor = clampPoint(session.startLocation, to: bounds)
            state.scaleX = clampScale(base + cfg.tension * fx, limit: limit)
            state.scaleY = clampScale(base + cfg.tension * fy, limit: limit)
            // The content leans a little toward the finger.
            let lean = cfg.tension * 0.5
            let maxLean = limit * min(width, height)
            state.translation = CGVector(
                dx: (d.dx * lean).clamped(to: -maxLean...maxLean),
                dy: (d.dy * lean).clamped(to: -maxLean...maxLean)
            )

        case .shear:
            state.anchor = clampPoint(session.startLocation, to: bounds)
            state.scaleX = base
            state.scaleY = base
            let shearLimit = limit
            state.shearX = (cfg.tension * d.dx / width).clamped(to: -shearLimit...shearLimit)
            state.shearY = (cfg.tension * d.dy / height).clamped(to: -shearLimit...shearLimit)
        }
        return state
    }

    /// The resting state that keeps the current anchor.
    public func restingState(for session: TouchSession, in bounds: CGRect) -> DeformationState {
        switch configuration.mode {
        case .uniformScale:
            return .identity(anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        case .anchoredScale, .displacement, .shear:
            return .identity(anchor: clampPoint(session.startLocation, to: bounds))
        }
    }

    private func clampScale(_ s: CGFloat, limit: CGFloat) -> CGFloat {
        s.clamped(to: (1 - limit)...(1 + limit))
    }

    private func clampPoint(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: p.x.clamped(to: rect.minX...max(rect.minX, rect.maxX)),
            y: p.y.clamped(to: rect.minY...max(rect.minY, rect.maxY))
        )
    }
}
