#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

public extension View {
    /// Adds TouchDynamics feedback to this view.
    ///
    /// ```swift
    /// CommentRow(comment: comment)
    ///     .touchDynamics()
    /// ```
    ///
    /// Touches are observed, never claimed: taps, scrolls, swipes and
    /// navigation gestures keep working. The effect surface never participates
    /// in hit-testing, and deformation is applied with a `GeometryEffect` that
    /// is ignored by layout.
    func touchDynamics(_ configuration: TouchDynamicsConfiguration = .default) -> some View {
        modifier(TouchDynamicsModifier(configuration: configuration, clipPath: nil))
    }

    /// Adds TouchDynamics feedback clipped to `clipShape`.
    ///
    /// ```swift
    /// Card()
    ///     .touchDynamics(.elastic, clipShape: RoundedRectangle(cornerRadius: 16))
    /// ```
    func touchDynamics<S: Shape>(_ configuration: TouchDynamicsConfiguration = .default, clipShape: S) -> some View {
        modifier(TouchDynamicsModifier(configuration: configuration, clipPath: { rect in
            clipShape.path(in: rect).cgPath
        }))
    }
}

struct TouchDynamicsModifier: ViewModifier {
    let configuration: TouchDynamicsConfiguration
    let clipPath: ((CGRect) -> CGPath)?

    @StateObject private var model = TouchDynamicsSwiftUIModel()

    func body(content: Content) -> some View {
        Group {
            if configuration.illumination.placement == .beneathContent {
                content.background { surface }
            } else {
                content.overlay { surface }
            }
        }
        .modifier(DeformationGeometryEffect(state: model.deformation).ignoredByLayout())
    }

    private var surface: some View {
        TouchDynamicsSurface(configuration: configuration, clipPath: clipPath, model: model)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Publishes the deformation state SwiftUI animates.
@MainActor
final class TouchDynamicsSwiftUIModel: ObservableObject {
    @Published var deformation: DeformationState = .identity

    func apply(_ state: DeformationState, animation: DeformationAnimation) {
        switch animation {
        case .none:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { deformation = state }
        case .easeOut(let duration):
            withAnimation(.easeOut(duration: duration)) { deformation = state }
        case .spring(let spring):
            withAnimation(.interpolatingSpring(mass: spring.mass, stiffness: spring.stiffness, damping: spring.dampingCoefficient, initialVelocity: 0)) {
                deformation = state
            }
        }
    }
}

/// Hosts the effect surface and the attachment.
struct TouchDynamicsSurface: UIViewRepresentable {
    let configuration: TouchDynamicsConfiguration
    let clipPath: ((CGRect) -> CGPath)?
    let model: TouchDynamicsSwiftUIModel

    func makeUIView(context: Context) -> EffectHostView {
        let host = EffectHostView(frame: .zero)
        let model = model
        let attachment = TouchDynamicsAttachment(swiftUIHost: host, configuration: configuration) { state, animation in
            model.apply(state, animation: animation)
        }
        attachment.clipPathProvider = clipPath
        return host
    }

    func updateUIView(_ host: EffectHostView, context: Context) {
        guard let attachment = host.attachment else { return }
        if attachment.configuration != configuration {
            attachment.configuration = configuration
        }
        attachment.clipPathProvider = clipPath
    }

    static func dismantleUIView(_ host: EffectHostView, coordinator: ()) {
        host.attachment?.detach()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EffectHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

/// Applies a ``DeformationState`` as a rendering-only transform.
struct DeformationGeometryEffect: GeometryEffect {
    var state: DeformationState

    var animatableData: DeformationState {
        get { state }
        set { state = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(state.affineTransform(in: CGRect(origin: .zero, size: size), origin: .topLeft))
    }
}

extension DeformationState: AdditiveArithmetic, VectorArithmetic {
    public static var zero: DeformationState {
        DeformationState(scaleX: 0, scaleY: 0, shearX: 0, shearY: 0, translation: .zero, anchor: .zero)
    }

    public static func + (lhs: DeformationState, rhs: DeformationState) -> DeformationState {
        DeformationState(
            scaleX: lhs.scaleX + rhs.scaleX,
            scaleY: lhs.scaleY + rhs.scaleY,
            shearX: lhs.shearX + rhs.shearX,
            shearY: lhs.shearY + rhs.shearY,
            translation: CGVector(dx: lhs.translation.dx + rhs.translation.dx, dy: lhs.translation.dy + rhs.translation.dy),
            anchor: CGPoint(x: lhs.anchor.x + rhs.anchor.x, y: lhs.anchor.y + rhs.anchor.y)
        )
    }

    public static func - (lhs: DeformationState, rhs: DeformationState) -> DeformationState {
        DeformationState(
            scaleX: lhs.scaleX - rhs.scaleX,
            scaleY: lhs.scaleY - rhs.scaleY,
            shearX: lhs.shearX - rhs.shearX,
            shearY: lhs.shearY - rhs.shearY,
            translation: CGVector(dx: lhs.translation.dx - rhs.translation.dx, dy: lhs.translation.dy - rhs.translation.dy),
            anchor: CGPoint(x: lhs.anchor.x - rhs.anchor.x, y: lhs.anchor.y - rhs.anchor.y)
        )
    }

    public mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        scaleX *= k
        scaleY *= k
        shearX *= k
        shearY *= k
        translation = CGVector(dx: translation.dx * k, dy: translation.dy * k)
        anchor = CGPoint(x: anchor.x * k, y: anchor.y * k)
    }

    public var magnitudeSquared: Double {
        let values = [scaleX, scaleY, shearX, shearY, translation.dx, translation.dy, anchor.x, anchor.y]
        return Double(values.reduce(0) { $0 + $1 * $1 })
    }
}
#endif
