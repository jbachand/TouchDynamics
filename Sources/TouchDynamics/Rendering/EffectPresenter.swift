#if canImport(UIKit)
import UIKit

/// Turns ``EngineCommand``s into renderer and deformation calls.
///
/// The presenter resolves the appearance for each touch when it begins
/// (appearance, tint, accessibility) and keeps it for the touch's lifetime, so
/// a touch always finishes with the look it started with.
@MainActor
final class EffectPresenter {
    private(set) weak var host: EffectHostView?
    private(set) var renderer: any SurfaceRendering
    private(set) var rendererSelection: RendererSelection
    let deformation: any DeformationDriving

    var configuration: TouchDynamicsConfiguration {
        didSet { configurationDidChange(from: oldValue) }
    }

    /// Overridable for tests.
    var accessibilityStatusProvider: @MainActor () -> AccessibilityStatus = { AccessibilityStatus.current }

    var onRippleFinished: (@MainActor (TouchIdentifier) -> Void)?
    var onSettled: (@MainActor (TouchIdentifier) -> Void)?

    private var appearances: [TouchIdentifier: ResolvedEffectAppearance] = [:]
    private var deformationOwner: TouchIdentifier?
    private var generation = 0

    /// Number of touches the presenter is currently showing or finishing.
    var liveSessionCount: Int { appearances.count }

    init(host: EffectHostView, configuration: TouchDynamicsConfiguration, deformation: any DeformationDriving) {
        self.host = host
        self.configuration = configuration
        self.deformation = deformation
        let made = RendererFactory.make(configuration.rendering)
        self.renderer = made.renderer
        self.rendererSelection = made.selection
        renderer.install(in: host)
    }

    func hostDidLayout() {
        guard let host else { return }
        renderer.hostDidLayout(bounds: host.bounds)
    }

    private func configurationDidChange(from old: TouchDynamicsConfiguration) {
        guard old.rendering != configuration.rendering, appearances.isEmpty, let host else { return }
        renderer.uninstall()
        let made = RendererFactory.make(configuration.rendering)
        renderer = made.renderer
        rendererSelection = made.selection
        renderer.install(in: host)
    }

    // MARK: Commands

    func handle(_ command: EngineCommand) {
        guard let host else { return }
        let bounds = host.bounds
        switch command {
        case .illuminate(let session):
            illuminate(session, in: host, bounds: bounds)
        case .track(let session):
            guard let appearance = appearances[session.id] else { return }
            renderer.track(session, appearance: appearance)
            if deformationOwner == session.id, let el = appearance.elasticity {
                let state = DeformationField(configuration: el).state(for: session, in: bounds, emphasis: session.isLongPress ? 1.5 : 1)
                let smoothing: TimeInterval
                if case .follow(let s) = appearance.tracking { smoothing = max(0.03, s) } else { smoothing = 0.06 }
                deformation.apply(state, animation: .easeOut(duration: smoothing), completion: nil)
            }
        case .longPress(let session):
            guard let appearance = appearances[session.id] else { return }
            renderer.emphasize(session, appearance: appearance)
            if deformationOwner == session.id, let el = appearance.elasticity {
                let state = DeformationField(configuration: el).state(for: session, in: bounds, emphasis: 1.5)
                deformation.apply(state, animation: .easeOut(duration: 0.25), completion: nil)
            }
        case .release(let session, let ripple):
            finish(session, in: host, bounds: bounds) { appearance, colors, done in
                self.renderer.release(
                    session,
                    ripple: ripple,
                    appearance: appearance,
                    colors: colors,
                    rippleDidFinish: { [weak self] in self?.onRippleFinished?(session.id) },
                    completion: done
                )
            }
        case .dissipate(let session, let immediate):
            finish(session, in: host, bounds: bounds, immediate: immediate) { appearance, _, done in
                self.renderer.dissipate(session, immediate: immediate, appearance: appearance, completion: done)
            }
        case .reset:
            generation += 1
            appearances.removeAll()
            deformationOwner = nil
            renderer.reset()
            deformation.reset()
        }
    }

    private func illuminate(_ session: TouchSession, in host: EffectHostView, bounds: CGRect) {
        let appearance = ResolvedEffectAppearance(
            configuration: configuration,
            style: host.traitCollection.userInterfaceStyle == .dark ? .dark : .light,
            accessibility: accessibilityStatusProvider()
        )
        appearances[session.id] = appearance
        host.layer.compositingFilter = appearance.compositingFilterName
        renderer.illuminate(session, appearance: appearance, colors: colors(for: appearance, in: host))
        if let el = appearance.elasticity {
            deformationOwner = session.id
            let state = DeformationField(configuration: el).state(for: session, in: bounds)
            deformation.apply(state, animation: .easeOut(duration: el.pressDuration), completion: nil)
        }
    }

    /// Runs the surface exit and the deformation spring, then reports settle
    /// once both are done.
    private func finish(
        _ session: TouchSession,
        in host: EffectHostView,
        bounds: CGRect,
        immediate: Bool = false,
        surfaceExit: (ResolvedEffectAppearance, ResolvedEffectColors, @escaping @MainActor () -> Void) -> Void
    ) {
        let appearance = appearances.removeValue(forKey: session.id) ?? ResolvedEffectAppearance(
            configuration: configuration,
            style: host.traitCollection.userInterfaceStyle == .dark ? .dark : .light,
            accessibility: accessibilityStatusProvider()
        )
        let gen = generation
        var pending = 2
        let done: @MainActor () -> Void = { [weak self] in
            pending -= 1
            guard pending == 0, let self, self.generation == gen else { return }
            self.onSettled?(session.id)
        }
        surfaceExit(appearance, colors(for: appearance, in: host), done)

        if deformationOwner == session.id, let el = appearance.elasticity {
            deformationOwner = nil
            let resting = DeformationField(configuration: el).restingState(for: session, in: bounds)
            deformation.apply(resting, animation: immediate ? .none : .spring(el.spring), completion: done)
        } else {
            done()
        }
    }

    private func colors(for appearance: ResolvedEffectAppearance, in host: EffectHostView) -> ResolvedEffectColors {
        let traits = host.traitCollection
        let tint = host.tintColor
        let illumination = configuration.illumination.color.resolve(style: appearance.style, traits: traits, tint: tint)
        let ripple = configuration.ripple.color?.resolve(style: appearance.style, traits: traits, tint: tint) ?? illumination
        return ResolvedEffectColors(illumination: illumination, ripple: ripple)
    }
}
#endif
