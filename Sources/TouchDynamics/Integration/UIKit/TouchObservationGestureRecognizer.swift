#if canImport(UIKit)
import UIKit

/// A gesture recognizer that only observes.
///
/// It never leaves the `.possible` state on its own, cannot prevent any other
/// recognizer and cannot be prevented by one, does not cancel or delay touches
/// to views, and recognizes simultaneously with everything. One instance is
/// installed per `UIWindow` and routes touches to registered surfaces.
@MainActor
final class TouchObservationGestureRecognizer: UIGestureRecognizer {
    let router: WindowTouchRouter

    init(router: WindowTouchRouter) {
        self.router = router
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
        ]
        name = "com.touchdynamics.observer"
        delegate = router
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        router.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        router.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        router.touchesEnded(touches, with: event)
        failIfSequenceIsOver(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        router.touchesCancelled(touches, with: event)
        failIfSequenceIsOver(event)
    }

    /// Moves to `.failed` once every touch in the window has lifted so UIKit
    /// resets the recognizer for the next sequence.
    private func failIfSequenceIsOver(_ event: UIEvent) {
        let live = event.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
        if !live {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        router.recognizerDidReset()
    }
}

/// A touch together with the identifier assigned to it at touch-down.
///
/// UIKit reuses `UITouch` objects across the taps of a multi-tap sequence, so
/// object identity cannot distinguish the second tap of a double tap from the
/// first; the router hands out a fresh identifier for every touch-down.
struct RoutedTouch {
    let touch: UITouch
    let id: TouchIdentifier
}

/// A view-backed surface that receives routed touches.
@MainActor
protocol TouchSurface: AnyObject {
    /// The view whose bounds define the hit region and coordinate space.
    var regionView: UIView? { get }
    var isObservationEnabled: Bool { get }
    func accepts(_ touch: UITouch) -> Bool
    func observedTouchesBegan(_ touches: [RoutedTouch], with event: UIEvent)
    func observedTouchesMoved(_ touches: [RoutedTouch], with event: UIEvent)
    func observedTouchesEnded(_ touches: [RoutedTouch], with event: UIEvent)
    func observedTouchesCancelled(_ touches: [RoutedTouch], with event: UIEvent)
}

/// Routes window touches to the innermost registered surface under the finger.
///
/// Resolution uses the touch's hit-test view: a surface matches when the hit
/// view is inside the surface's region view, or the region view is inside the
/// hit view (SwiftUI content and non-interactive UIKit views). Among matches
/// the deepest region wins, then the smallest.
@MainActor
final class WindowTouchRouter: NSObject, UIGestureRecognizerDelegate {
    private struct WeakSurface {
        weak var surface: (any TouchSurface)?
    }

    private struct Route {
        weak var surface: (any TouchSurface)?
        let id: TouchIdentifier
    }

    private var entries: [WeakSurface] = []
    private var routes: [ObjectIdentifier: Route] = [:]
    private var nextIdentifier: UInt = 1
    private weak var recognizer: TouchObservationGestureRecognizer?

    /// The router for `window`, creating and installing one if needed.
    static func router(for window: UIWindow) -> WindowTouchRouter {
        if let existing = window.gestureRecognizers?.lazy.compactMap({ $0 as? TouchObservationGestureRecognizer }).first {
            return existing.router
        }
        let router = WindowTouchRouter()
        let recognizer = TouchObservationGestureRecognizer(router: router)
        router.recognizer = recognizer
        window.addGestureRecognizer(recognizer)
        return router
    }

    /// The router for `window` without creating one.
    static func existingRouter(for window: UIWindow) -> WindowTouchRouter? {
        window.gestureRecognizers?.lazy.compactMap({ $0 as? TouchObservationGestureRecognizer }).first?.router
    }

    var surfaceCount: Int {
        compact()
        return entries.count
    }

    func register(_ surface: any TouchSurface) {
        compact()
        guard !entries.contains(where: { $0.surface === surface }) else { return }
        entries.append(WeakSurface(surface: surface))
    }

    func unregister(_ surface: any TouchSurface) {
        entries.removeAll { $0.surface == nil || $0.surface === surface }
        routes = routes.filter { $0.value.surface != nil && $0.value.surface !== surface }
        if entries.isEmpty, let recognizer, routes.isEmpty {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
    }

    private func compact() {
        entries.removeAll { $0.surface == nil }
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        resolve(touch)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func resolve(_ touch: UITouch) -> Bool {
        compact()
        let hitView = touch.view
        var best: (surface: any TouchSurface, depth: Int, area: CGFloat)?
        for entry in entries {
            guard let surface = entry.surface, surface.isObservationEnabled, let region = surface.regionView else { continue }
            guard region.window != nil, !region.isHidden, region.alpha > 0.02 else { continue }
            guard surface.accepts(touch) else { continue }
            let p = touch.location(in: region)
            guard region.bounds.contains(p) else { continue }
            if let hitView {
                guard hitView.isDescendant(of: region) || region.isDescendant(of: hitView) else { continue }
            }
            let depth = region.hierarchyDepth
            let area = region.bounds.width * region.bounds.height
            if let current = best {
                if depth > current.depth || (depth == current.depth && area < current.area) {
                    best = (surface, depth, area)
                }
            } else {
                best = (surface, depth, area)
            }
        }
        guard let best else { return false }
        routes[ObjectIdentifier(touch)] = Route(surface: best.surface, id: TouchIdentifier(rawValue: nextIdentifier))
        nextIdentifier &+= 1
        if nextIdentifier == 0 { nextIdentifier = 1 }
        return true
    }

    // MARK: Touch dispatch

    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        dispatch(touches) { $0.observedTouchesBegan($1, with: event) }
    }

    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        dispatch(touches) { $0.observedTouchesMoved($1, with: event) }
    }

    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        dispatch(touches) { $0.observedTouchesEnded($1, with: event) }
        for touch in touches { routes[ObjectIdentifier(touch)] = nil }
    }

    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        dispatch(touches) { $0.observedTouchesCancelled($1, with: event) }
        for touch in touches { routes[ObjectIdentifier(touch)] = nil }
    }

    func recognizerDidReset() {
        routes.removeAll()
    }

    private func dispatch(_ touches: Set<UITouch>, _ body: (any TouchSurface, [RoutedTouch]) -> Void) {
        var grouped: [ObjectIdentifier: (any TouchSurface, [RoutedTouch])] = [:]
        for touch in touches {
            guard let route = routes[ObjectIdentifier(touch)], let surface = route.surface else { continue }
            let key = ObjectIdentifier(surface)
            let routed = RoutedTouch(touch: touch, id: route.id)
            if var existing = grouped[key] {
                existing.1.append(routed)
                grouped[key] = existing
            } else {
                grouped[key] = (surface, [routed])
            }
        }
        for (_, pair) in grouped {
            body(pair.0, pair.1)
        }
    }
}
#endif
