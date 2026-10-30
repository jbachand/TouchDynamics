#if canImport(UIKit)
import UIKit

/// Resolved colors for one touch.
struct ResolvedEffectColors {
    var illumination: CGColor
    var ripple: CGColor
}

/// Draws illumination and ripple into an ``EffectHostView``.
///
/// Renderers are stateless with respect to gesture logic; they only react to
/// the presenter's calls and report completion through the closures.
@MainActor
protocol SurfaceRendering: AnyObject {
    func install(in host: EffectHostView)
    func uninstall()
    func hostDidLayout(bounds: CGRect)
    func illuminate(_ session: TouchSession, appearance: ResolvedEffectAppearance, colors: ResolvedEffectColors)
    func track(_ session: TouchSession, appearance: ResolvedEffectAppearance)
    func emphasize(_ session: TouchSession, appearance: ResolvedEffectAppearance)
    func release(
        _ session: TouchSession,
        ripple: Bool,
        appearance: ResolvedEffectAppearance,
        colors: ResolvedEffectColors,
        rippleDidFinish: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor () -> Void
    )
    func dissipate(
        _ session: TouchSession,
        immediate: Bool,
        appearance: ResolvedEffectAppearance,
        completion: @escaping @MainActor () -> Void
    )
    func reset()
}

/// Applies ``DeformationState``s to the host content.
@MainActor
protocol DeformationDriving: AnyObject {
    /// The state most recently applied (model value, not presentation).
    var currentState: DeformationState { get }
    func apply(_ state: DeformationState, animation: DeformationAnimation, completion: (@MainActor () -> Void)?)
    func reset()
}

@MainActor
enum RendererFactory {
    static func make(_ configuration: RenderingConfiguration) -> (renderer: any SurfaceRendering, selection: RendererSelection) {
        switch configuration.renderer {
        case .automatic, .coreAnimation:
            return (CoreAnimationSurfaceRenderer(maximumRipples: configuration.maximumConcurrentRipples), .coreAnimation)
        case .metal:
            if let metal = MetalSurfaceRenderer(frameRate: configuration.preferredFrameRate, maximumRipples: configuration.maximumConcurrentRipples) {
                return (metal, .metal)
            }
            return (CoreAnimationSurfaceRenderer(maximumRipples: configuration.maximumConcurrentRipples), .coreAnimation)
        }
    }
}

extension EffectColor {
    /// Resolves to a concrete color for the given appearance. Alpha is the
    /// color's own alpha; renderers multiply it by the effect intensity.
    @MainActor
    func resolve(style: EffectAppearanceStyle, traits: UITraitCollection, tint: UIColor?) -> CGColor {
        switch self {
        case .adaptive:
            return UIColor.white.cgColor
        case .adaptiveInk:
            return style == .dark ? UIColor.white.cgColor : UIColor.black.cgColor
        case .tint:
            return (tint ?? .tintColor).resolvedColor(with: traits).cgColor
        case .rgba(let r, let g, let b, let a):
            return UIColor(red: r, green: g, blue: b, alpha: a).cgColor
        case .uiColor(let color):
            return color.resolvedColor(with: traits).cgColor
        }
    }
}

extension CGColor {
    /// A copy whose alpha is `alpha × multiplier`, clamped to `0...1`.
    func scaledAlpha(_ multiplier: CGFloat) -> CGColor {
        let a = (alpha * multiplier).clamped(to: 0...1)
        return copy(alpha: a) ?? self
    }

    /// Relative luminance in sRGB, `0...1`.
    var relativeLuminance: CGFloat {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = converted(to: space, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return 1 }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }
}

extension UIView {
    /// Number of superviews above this view.
    var hierarchyDepth: Int {
        var depth = 0
        var v = superview
        while let current = v {
            depth += 1
            v = current.superview
        }
        return depth
    }
}
#endif
