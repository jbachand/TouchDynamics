#if canImport(UIKit)
import UIKit

/// The view that hosts effect layers. It is inserted into the target (UIKit)
/// or placed as a SwiftUI overlay. It never participates in hit-testing or
/// accessibility, and it owns the attachment so the attachment lives exactly
/// as long as the effect is installed.
@MainActor
final class EffectHostView: UIView {
    /// Strong: the host keeps the attachment alive while installed.
    var attachment: TouchDynamicsAttachment?
    var clipShape: EffectClipShape = .automatic {
        didSet { setNeedsLayout() }
    }
    var clipPathProvider: ((CGRect) -> CGPath)? {
        didSet { setNeedsLayout() }
    }
    /// The view whose corner radius is mirrored under `.automatic` clipping.
    weak var clipReferenceView: UIView?

    private let shapeMask = CAShapeLayer()
    private var lastClipBounds: CGRect = .null

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        layer.masksToBounds = true
        layer.allowsGroupOpacity = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EffectHostView is created programmatically")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachment?.hostDidMove(toWindow: window)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil {
            attachment?.hostWasRemovedFromSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateClipping()
        attachment?.hostDidLayout()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    // MARK: Clipping

    func updateClipping() {
        let b = bounds
        switch clipShape {
        case .none:
            layer.mask = nil
            layer.masksToBounds = false
            layer.cornerRadius = 0
        case .automatic:
            layer.mask = nil
            layer.masksToBounds = true
            if let provider = clipPathProvider {
                installMask(provider(b))
            } else if let reference = clipReferenceView?.layer {
                layer.cornerRadius = reference.cornerRadius
                layer.cornerCurve = reference.cornerCurve
                layer.maskedCorners = reference.maskedCorners
            } else {
                layer.cornerRadius = 0
            }
        case .rectangle:
            layer.mask = nil
            layer.masksToBounds = true
            layer.cornerRadius = 0
        case .roundedRectangle(let radius):
            layer.mask = nil
            layer.masksToBounds = true
            layer.cornerRadius = min(radius, min(b.width, b.height) / 2)
            layer.cornerCurve = .continuous
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .capsule:
            layer.mask = nil
            layer.masksToBounds = true
            layer.cornerRadius = min(b.width, b.height) / 2
            layer.cornerCurve = .circular
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .ellipse:
            layer.cornerRadius = 0
            layer.masksToBounds = true
            installMask(CGPath(ellipseIn: b, transform: nil))
        }
        lastClipBounds = b
    }

    private func installMask(_ path: CGPath) {
        layer.cornerRadius = 0
        shapeMask.frame = bounds
        shapeMask.path = path
        layer.mask = shapeMask
    }
}
#endif
