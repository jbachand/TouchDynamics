#if canImport(UIKit)
import UIKit

/// Deforms a `UIView` through its `transform`, composed on top of whatever
/// transform the view had when the press began.
///
/// If the host application changes the view's transform during a press (for
/// example its own highlight animation), the driver steps aside for the rest
/// of that press rather than fighting over the property.
@MainActor
final class ViewTransformDeformationDriver: DeformationDriving {
    private(set) weak var view: UIView?
    private(set) var currentState: DeformationState = .identity
    private var baseTransform: CGAffineTransform?
    private var lastApplied: CGAffineTransform?
    private var animator: UIViewPropertyAnimator?
    private var pendingCompletion: (@MainActor () -> Void)?
    private var isCompromised = false

    init(view: UIView) {
        self.view = view
    }

    func apply(_ state: DeformationState, animation: DeformationAnimation, completion: (@MainActor () -> Void)?) {
        guard let view else {
            completion?()
            return
        }
        if baseTransform == nil {
            baseTransform = view.transform
        } else if animator == nil, let last = lastApplied, !view.transform.isApproximatelyEqual(to: last) {
            // Someone else owns the transform now.
            isCompromised = true
        }

        // A new target supersedes the one in flight: stop where it is (that
        // value is ours) and report the superseded move as done.
        let superseded = pendingCompletion
        pendingCompletion = nil
        if let running = animator {
            running.stopAnimation(true)
            animator = nil
            lastApplied = view.transform
        }
        superseded?()

        guard !isCompromised, let base = baseTransform else {
            completion?()
            return
        }

        currentState = state
        let target = state.affineTransform(in: view.bounds, origin: .center).concatenating(base)

        let settle: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.lastApplied = target
            if state.isIdentity {
                self.baseTransform = nil
                self.lastApplied = nil
            }
        }

        switch animation {
        case .none:
            view.transform = target
            settle()
            completion?()
        case .easeOut(let duration) where duration <= 0:
            view.transform = target
            settle()
            completion?()
        case .easeOut(let duration):
            let a = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                view.transform = target
            }
            run(a, settle: settle, completion: completion)
        case .spring(let solver):
            let params = UISpringTimingParameters(
                mass: solver.mass,
                stiffness: solver.stiffness,
                damping: solver.dampingCoefficient,
                initialVelocity: .zero
            )
            let a = UIViewPropertyAnimator(duration: 0, timingParameters: params)
            a.addAnimations { view.transform = target }
            run(a, settle: settle, completion: completion)
        }
    }

    private func run(_ a: UIViewPropertyAnimator, settle: @escaping @MainActor () -> Void, completion: (@MainActor () -> Void)?) {
        a.isUserInteractionEnabled = true
        a.isInterruptible = true
        pendingCompletion = completion
        a.addCompletion { [weak self] position in
            guard let self, self.animator === a else { return }
            self.animator = nil
            guard position == .end else { return }
            settle()
            let done = self.pendingCompletion
            self.pendingCompletion = nil
            done?()
        }
        animator = a
        a.startAnimation()
    }

    func reset() {
        pendingCompletion = nil
        animator?.stopAnimation(true)
        animator = nil
        if let view, let base = baseTransform, !isCompromised {
            view.transform = base
        }
        baseTransform = nil
        lastApplied = nil
        isCompromised = false
        currentState = .identity
    }
}

/// Forwards deformation states to a closure (SwiftUI drives the animation).
/// Completion is estimated from the animation's duration or spring settle time.
@MainActor
final class ClosureDeformationDriver: DeformationDriving {
    typealias Sink = @MainActor (DeformationState, DeformationAnimation) -> Void

    private let sink: Sink
    private(set) var currentState: DeformationState = .identity
    private var generation = 0
    private var pendingCompletion: (@MainActor () -> Void)?

    init(sink: @escaping Sink) {
        self.sink = sink
    }

    func apply(_ state: DeformationState, animation: DeformationAnimation, completion: (@MainActor () -> Void)?) {
        currentState = state
        sink(state, animation)
        generation += 1
        let gen = generation
        // SwiftUI retargets the running animation; the superseded move is done.
        let superseded = pendingCompletion
        pendingCompletion = nil
        superseded?()
        let delay: TimeInterval
        switch animation {
        case .none:
            delay = 0
        case .easeOut(let d):
            delay = d
        case .spring(let s):
            delay = s.settlingDuration(initialDisplacement: 1, tolerance: 0.002)
        }
        guard let completion else { return }
        if delay <= 0 {
            completion()
            return
        }
        pendingCompletion = completion
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.generation == gen else { return }
            self.pendingCompletion = nil
            completion()
        }
    }

    func reset() {
        generation += 1
        pendingCompletion = nil
        guard !currentState.isIdentity else { return }
        currentState = .identity
        // Reset can run inside a SwiftUI view update (dismantle, window change);
        // publishing there is undefined behavior, so defer one turn.
        let sink = self.sink
        Task { @MainActor in
            sink(.identity, .none)
        }
    }
}

extension CGAffineTransform {
    func isApproximatelyEqual(to other: CGAffineTransform, tolerance: CGFloat = 1e-4) -> Bool {
        abs(a - other.a) < tolerance && abs(b - other.b) < tolerance
            && abs(c - other.c) < tolerance && abs(d - other.d) < tolerance
            && abs(tx - other.tx) < tolerance && abs(ty - other.ty) < tolerance
    }
}
#endif
