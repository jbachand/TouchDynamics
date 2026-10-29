#if canImport(UIKit)
import UIKit

/// Learns when an ancestor `UIScrollView` starts scrolling by adding a
/// target-action to its pan gesture recognizer. Observation is nonexclusive:
/// nothing about the scroll view's own behavior changes.
@MainActor
final class ScrollTakeoverObserver: NSObject {
    var onScrollBegan: (@MainActor () -> Void)?
    var onScrollEnded: (@MainActor () -> Void)?

    private let observed = NSHashTable<UIPanGestureRecognizer>.weakObjects()

    /// Observes every `UIScrollView` above `view`.
    func beginObserving(ancestorsOf view: UIView) {
        var current = view.superview
        while let v = current {
            if let scrollView = v as? UIScrollView {
                let pan = scrollView.panGestureRecognizer
                if !observed.contains(pan) {
                    pan.addTarget(self, action: #selector(panDidChange(_:)))
                    observed.add(pan)
                }
            }
            current = v.superview
        }
    }

    func endObserving() {
        for pan in observed.allObjects {
            pan.removeTarget(self, action: #selector(panDidChange(_:)))
        }
        observed.removeAllObjects()
    }

    /// Fallback check: an observed scroll view is dragging or decelerating.
    var isAnyObservedScrollViewMoving: Bool {
        observed.allObjects.contains { pan in
            guard let scrollView = pan.view as? UIScrollView else { return false }
            return scrollView.isDragging || scrollView.isDecelerating
        }
    }

    var observedCount: Int { observed.count }

    @objc private func panDidChange(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            onScrollBegan?()
        case .ended, .cancelled, .failed:
            onScrollEnded?()
        default:
            break
        }
    }
}
#endif
