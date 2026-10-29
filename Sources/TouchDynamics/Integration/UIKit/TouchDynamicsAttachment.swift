#if canImport(UIKit)
import UIKit

/// The live binding between a view and TouchDynamics.
///
/// Create one with ``TouchDynamics/attach(to:configuration:)`` (UIKit) or by
/// applying the SwiftUI modifier. The attachment owns the engine, the renderer
/// and the deformation driver for its view; the effect host view owns the
/// attachment, so it lives exactly as long as the effect is installed. Call
/// ``detach()`` to remove everything, or ``reset()`` to cancel effects
/// immediately (for example from `prepareForReuse`).
@MainActor
public final class TouchDynamicsAttachment {
    /// How the attachment was created.
    public enum Mode: Sendable, Equatable {
        case uiKit
        case swiftUI
    }

    public let mode: Mode
    /// The UIKit view the effects are attached to. `nil` in SwiftUI mode.
    public private(set) weak var view: UIView?
    /// The configuration. Changes apply to subsequent touches.
    public var configuration: TouchDynamicsConfiguration {
        didSet { applyConfiguration() }
    }
    /// Pauses touch observation without removing anything.
    public var isEnabled = true
    /// Custom clip path for the effect surface, evaluated in surface bounds.
    public var clipPathProvider: ((CGRect) -> CGPath)? {
        didSet { host?.clipPathProvider = clipPathProvider }
    }
    /// The state machine behind this attachment.
    public let engine: TouchInteractionEngine
    /// Aggregate engine state.
    public var state: TouchEngineState { engine.state }
    /// Whether the effect host is installed in a view.
    public var isAttached: Bool { !isDetached && host?.superview != nil }
    /// The renderer actually in use after automatic selection and fallback.
    public var activeRenderer: RendererSelection { presenter.rendererSelection }

    weak var host: EffectHostView?
    let presenter: EffectPresenter
    let scrollObserver = ScrollTakeoverObserver()
    private weak var router: WindowTouchRouter?
    private var longPressTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var isDetached = false

    // MARK: Creation

    /// UIKit mode: installs an effect host into `target`.
    init(target: UIView, configuration: TouchDynamicsConfiguration) {
        self.mode = .uiKit
        self.view = target
        self.configuration = configuration

        let container = Self.container(for: target)
        let host = EffectHostView(frame: container.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.clipReferenceView = target
        host.clipShape = configuration.rendering.clipShape
        self.host = host

        let deformationView = Self.deformationView(for: target)
        let driver = ViewTransformDeformationDriver(view: deformationView)
        self.presenter = EffectPresenter(host: host, configuration: configuration, deformation: driver)
        self.engine = TouchInteractionEngine(configuration: configuration.gesture, bounds: host.bounds)

        wire()
        Self.insert(host, into: container, placement: Self.resolvedPlacement(configuration.illumination.placement, target: target))
        host.attachment = self
        hostDidMove(toWindow: host.window)
    }

    /// SwiftUI mode: the representable's view is the host and the region.
    init(swiftUIHost host: EffectHostView, configuration: TouchDynamicsConfiguration, deformationSink: @escaping ClosureDeformationDriver.Sink) {
        self.mode = .swiftUI
        self.view = nil
        self.configuration = configuration
        self.host = host
        host.clipShape = configuration.rendering.clipShape
        let driver = ClosureDeformationDriver(sink: deformationSink)
        self.presenter = EffectPresenter(host: host, configuration: configuration, deformation: driver)
        self.engine = TouchInteractionEngine(configuration: configuration.gesture, bounds: host.bounds)
        wire()
        host.attachment = self
        hostDidMove(toWindow: host.window)
    }

    private func wire() {
        engine.onCommand = { [weak self] command in
            self?.presenter.handle(command)
        }
        presenter.onRippleFinished = { [weak self] id in
            self?.engine.rippleDidFinish(id)
        }
        presenter.onSettled = { [weak self] id in
            self?.engine.effectDidSettle(id)
        }
    }

    private func applyConfiguration() {
        engine.configuration = configuration.gesture
        presenter.configuration = configuration
        host?.clipShape = configuration.rendering.clipShape
        if mode == .uiKit, let host, let target = view, let container = host.superview {
            let placement = Self.resolvedPlacement(configuration.illumination.placement, target: target)
            Self.order(host, in: container, placement: placement)
        }
    }

    // MARK: Lifecycle

    /// Cancels every running effect immediately and clears all touch state.
    public func reset() {
        longPressTask?.cancel()
        longPressTask = nil
        settleTask?.cancel()
        settleTask = nil
        scrollObserver.endObserving()
        engine.reset()
    }

    /// Removes the effect host, stops observing touches and frees resources.
    /// The attachment is inert afterwards.
    public func detach() {
        guard !isDetached else { return }
        reset()
        isDetached = true
        engine.detach()
        router?.unregister(self)
        router = nil
        if let host {
            host.attachment = nil
            host.removeFromSuperview()
        }
        presenter.renderer.uninstall()
    }

    // MARK: Host callbacks

    func hostDidMove(toWindow window: UIWindow?) {
        if let router, router !== window.map(WindowTouchRouter.router(for:)) {
            router.unregister(self)
            self.router = nil
        }
        guard !isDetached else { return }
        if let window {
            let router = WindowTouchRouter.router(for: window)
            router.register(self)
            self.router = router
            engine.bounds = host?.bounds ?? .zero
        } else if !engine.isIdle || presenter.liveSessionCount > 0 {
            // Leaving the window (cell reuse, dismissal): nothing may linger.
            reset()
        }
    }

    func hostWasRemovedFromSuperview() {
        guard mode == .uiKit, !isDetached else { return }
        // Someone removed the host from the target; treat as detach.
        detach()
    }

    func hostDidLayout() {
        guard let host else { return }
        engine.bounds = host.bounds
        presenter.hostDidLayout()
    }

    // MARK: Touch routing

    private func location(of touch: UITouch, in host: EffectHostView) -> CGPoint {
        let local = touch.location(in: host)
        let current = presenter.deformation.currentState
        guard !current.isIdentity else { return local }
        // Undo our own deformation so locations are in resting geometry.
        return local.applying(current.affineTransform(in: host.bounds, origin: .topLeft))
    }

    private func scheduleLongPressCheck() {
        longPressTask?.cancel()
        let delay = configuration.gesture.longPressDuration
        longPressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.engine.tick()
        }
    }

    private func scheduleSettleCheck() {
        settleTask?.cancel()
        let delay = engine.settleTimeout + 0.05
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.engine.tick()
        }
    }

    private func fingersLifted() {
        guard engine.activeSessions.isEmpty else { return }
        scrollObserver.endObserving()
        longPressTask?.cancel()
        longPressTask = nil
        scheduleSettleCheck()
    }

    // MARK: Helpers

    static func container(for target: UIView) -> UIView {
        if let cell = target as? UITableViewCell { return cell.contentView }
        if let cell = target as? UICollectionViewCell { return cell.contentView }
        return target
    }

    static func deformationView(for target: UIView) -> UIView {
        container(for: target)
    }

    static func resolvedPlacement(_ placement: EffectPlacement, target: UIView) -> EffectPlacement {
        switch placement {
        case .automatic:
            return target is UIControl ? .aboveContent : .beneathContent
        case .beneathContent, .aboveContent:
            return placement
        }
    }

    static func insert(_ host: EffectHostView, into container: UIView, placement: EffectPlacement) {
        switch placement {
        case .aboveContent:
            container.addSubview(host)
        case .beneathContent, .automatic:
            container.insertSubview(host, at: 0)
        }
    }

    static func order(_ host: EffectHostView, in container: UIView, placement: EffectPlacement) {
        switch placement {
        case .aboveContent:
            container.bringSubviewToFront(host)
        case .beneathContent, .automatic:
            container.sendSubviewToBack(host)
        }
    }
}

// MARK: - TouchSurface

extension TouchDynamicsAttachment: TouchSurface {
    var regionView: UIView? {
        switch mode {
        case .uiKit: return view
        case .swiftUI: return host
        }
    }

    var isObservationEnabled: Bool {
        isEnabled && !isDetached && host != nil
    }

    func accepts(_ touch: UITouch) -> Bool {
        switch touch.type {
        case .direct, .pencil:
            return true
        case .indirectPointer:
            return configuration.gesture.acceptsIndirectPointer
        default:
            return false
        }
    }

    func observedTouchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let host else { return }
        if engine.activeSessions.isEmpty {
            scrollObserver.beginObserving(ancestorsOf: host)
            scrollObserver.onScrollBegan = { [weak self] in self?.engine.scrollDidBegin() }
            scrollObserver.onScrollEnded = { [weak self] in self?.engine.scrollDidEnd() }
            engine.bounds = host.bounds
            settleTask?.cancel()
            settleTask = nil
        }
        for touch in touches {
            engine.handle(.began(id: TouchIdentifier(object: touch), location: location(of: touch, in: host), time: touch.timestamp))
        }
        scheduleLongPressCheck()
    }

    func observedTouchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let host else { return }
        if !engine.isScrolling, scrollObserver.isAnyObservedScrollViewDragging {
            engine.scrollDidBegin()
        }
        for touch in touches {
            engine.handle(.moved(id: TouchIdentifier(object: touch), location: location(of: touch, in: host), time: touch.timestamp))
        }
    }

    func observedTouchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let host else { return }
        for touch in touches {
            engine.handle(.ended(id: TouchIdentifier(object: touch), location: location(of: touch, in: host), time: touch.timestamp))
        }
        fingersLifted()
    }

    func observedTouchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            engine.handle(.cancelled(id: TouchIdentifier(object: touch), time: touch.timestamp))
        }
        fingersLifted()
    }
}

// MARK: - Public UIKit API

public extension TouchDynamics {
    /// Attaches touch effects to `view`.
    ///
    /// No subclassing is required and the view's own gesture recognizers,
    /// control events and accessibility remain untouched. Attaching twice
    /// updates the configuration and returns the existing attachment.
    ///
    /// For `UITableViewCell` / `UICollectionViewCell` the effect is hosted in
    /// `contentView` and reset automatically when the cell leaves the window.
    @MainActor
    @discardableResult
    static func attach(to view: UIView, configuration: TouchDynamicsConfiguration = .default) -> TouchDynamicsAttachment {
        if let existing = view.touchDynamicsAttachment {
            existing.configuration = configuration
            return existing
        }
        return TouchDynamicsAttachment(target: view, configuration: configuration)
    }

    /// Removes a previous attachment from `view`, if any.
    @MainActor
    static func detach(from view: UIView) {
        view.touchDynamicsAttachment?.detach()
    }
}

public extension UIView {
    /// The TouchDynamics attachment installed on this view, if any.
    var touchDynamicsAttachment: TouchDynamicsAttachment? {
        let container = TouchDynamicsAttachment.container(for: self)
        for subview in container.subviews {
            if let host = subview as? EffectHostView, let attachment = host.attachment, attachment.view === self {
                return attachment
            }
        }
        return nil
    }
}
#endif
