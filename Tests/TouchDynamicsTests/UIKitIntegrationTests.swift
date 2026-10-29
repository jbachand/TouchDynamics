#if canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
@testable import TouchDynamics

@MainActor
final class UIKitIntegrationTests: XCTestCase {
    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.isHidden = false
        return window
    }

    func testAttachInstallsHostBeneathContentAndIsIdempotent() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let label = UILabel()
        view.addSubview(label)

        let attachment = TouchDynamics.attach(to: view)
        XCTAssertTrue(view.touchDynamicsAttachment === attachment)
        XCTAssertEqual(attachment.mode, .uiKit)
        XCTAssertTrue(attachment.view === view)
        XCTAssertTrue(attachment.isAttached)
        XCTAssertEqual(view.subviews.count, 2)
        XCTAssertTrue(view.subviews.first is EffectHostView, "plain views host the effect beneath content")
        XCTAssertEqual(view.subviews.first?.bounds, view.bounds)
        XCTAssertFalse(view.subviews.first!.isUserInteractionEnabled)
        XCTAssertTrue(view.subviews.first!.accessibilityElementsHidden)

        let again = TouchDynamics.attach(to: view, configuration: .subtle)
        XCTAssertTrue(again === attachment)
        XCTAssertEqual(attachment.configuration, .subtle)
        XCTAssertEqual(view.subviews.count, 2)
    }

    func testControlsHostAboveContent() {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 120, height: 44)
        button.setTitle("Tap", for: .normal)
        button.layoutIfNeeded()
        TouchDynamics.attach(to: button)
        XCTAssertTrue(button.subviews.last is EffectHostView)
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertNil(button.gestureRecognizers?.first { $0 is TouchObservationGestureRecognizer }, "nothing is added to the control itself")
    }

    func testCellsHostInContentView() {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "c")
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        let attachment = TouchDynamics.attach(to: cell)
        XCTAssertTrue(cell.contentView.subviews.first is EffectHostView)
        XCTAssertTrue(cell.touchDynamicsAttachment === attachment)
        XCTAssertNil(cell.contentView.touchDynamicsAttachment, "the attachment belongs to the cell, not its content view")

        let collectionCell = UICollectionViewCell(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        TouchDynamics.attach(to: collectionCell)
        XCTAssertTrue(collectionCell.contentView.subviews.first is EffectHostView)
    }

    func testDetachRemovesEverything() {
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        let attachment = TouchDynamics.attach(to: view)
        XCTAssertNotNil(window.gestureRecognizers?.first { $0 is TouchObservationGestureRecognizer })

        attachment.detach()
        XCTAssertNil(view.touchDynamicsAttachment)
        XCTAssertFalse(attachment.isAttached)
        XCTAssertEqual(attachment.state, .detached)
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertNil(window.gestureRecognizers?.first { $0 is TouchObservationGestureRecognizer }, "the last surface removes the window observer")

        TouchDynamics.detach(from: view) // no-op
        XCTAssertNil(view.touchDynamicsAttachment)
    }

    func testWindowObserverIsSharedAndNonExclusive() {
        let window = makeWindow()
        let a = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let b = UIView(frame: CGRect(x: 0, y: 100, width: 200, height: 44))
        window.addSubview(a)
        window.addSubview(b)
        TouchDynamics.attach(to: a)
        TouchDynamics.attach(to: b)

        let observers = window.gestureRecognizers?.compactMap { $0 as? TouchObservationGestureRecognizer } ?? []
        XCTAssertEqual(observers.count, 1)
        let observer = observers[0]
        XCTAssertEqual(observer.router.surfaceCount, 2)
        XCTAssertFalse(observer.cancelsTouchesInView)
        XCTAssertFalse(observer.delaysTouchesBegan)
        XCTAssertFalse(observer.delaysTouchesEnded)
        XCTAssertFalse(observer.canPrevent(UITapGestureRecognizer()))
        XCTAssertFalse(observer.canBePrevented(by: UIPanGestureRecognizer()))
        XCTAssertTrue(observer.router.gestureRecognizer(observer, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
        XCTAssertEqual(observer.state, .possible)

        a.touchDynamicsAttachment?.detach()
        XCTAssertEqual(observer.router.surfaceCount, 1)
    }

    func testHostFollowsBoundsAndUpdatesEngine() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let attachment = TouchDynamics.attach(to: view)
        XCTAssertEqual(attachment.engine.bounds, CGRect(x: 0, y: 0, width: 200, height: 44))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        view.layoutIfNeeded()
        XCTAssertEqual(view.subviews.first?.bounds, CGRect(x: 0, y: 0, width: 300, height: 80))
        XCTAssertEqual(attachment.engine.bounds, CGRect(x: 0, y: 0, width: 300, height: 80))
    }

    func testAutomaticClippingMirrorsCornerRadius() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        TouchDynamics.attach(to: view)
        view.layoutIfNeeded()
        let host = view.subviews.first as! EffectHostView
        XCTAssertEqual(host.layer.cornerRadius, 12)
        XCTAssertEqual(host.layer.cornerCurve, .continuous)
        XCTAssertTrue(host.layer.masksToBounds)

        var config = TouchDynamicsConfiguration.default
        config.rendering.clipShape = .capsule
        view.touchDynamicsAttachment?.configuration = config
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(host.layer.cornerRadius, 22)

        config.rendering.clipShape = .none
        view.touchDynamicsAttachment?.configuration = config
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertFalse(host.layer.masksToBounds)

        config.rendering.clipShape = .ellipse
        view.touchDynamicsAttachment?.configuration = config
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertNotNil(host.layer.mask)
    }

    func testEngineCommandsDriveCoreAnimationLayersAndResetClearsThem() {
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        let attachment = TouchDynamics.attach(to: view)
        XCTAssertEqual(attachment.activeRenderer, .coreAnimation)
        let host = view.subviews.first as! EffectHostView

        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        XCTAssertEqual(host.layer.sublayers?.count, 1, "one illumination layer")
        let illumination = host.layer.sublayers!.first as! CAGradientLayer
        XCTAssertEqual(illumination.type, .radial)
        XCTAssertEqual(illumination.position, CGPoint(x: 30, y: 20), "illumination originates at the touch")
        XCTAssertEqual(illumination.bounds.width, TouchDynamicsConfiguration.default.illumination.radius * 2)
        XCTAssertNotEqual(view.transform, .identity, "press deformation is applied")
        XCTAssertEqual(host.layer.compositingFilter as? String, "multiplyBlendMode")

        attachment.engine.handle(.moved(id: .test(1), location: CGPoint(x: 36, y: 22), time: 0.05))
        XCTAssertEqual(illumination.position, CGPoint(x: 36, y: 22), "illumination follows the finger")

        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 36, y: 22), time: 0.1))
        let sublayers = host.layer.sublayers ?? []
        XCTAssertEqual(sublayers.count, 3, "illumination fading plus disc and ring")
        let ripples = sublayers.dropFirst().compactMap { $0 as? CAGradientLayer }
        XCTAssertEqual(ripples.count, 2)
        for ripple in ripples {
            XCTAssertEqual(ripple.position, CGPoint(x: 36, y: 22), "ripple originates at the release location")
            XCTAssertNotNil(ripple.animation(forKey: "td.locations"))
            XCTAssertNotNil(ripple.animation(forKey: "td.envelope"))
            XCTAssertGreaterThanOrEqual(ripple.bounds.width / 2, RippleWave.coverageRadius(from: CGPoint(x: 36, y: 22), in: view.bounds))
        }
        XCTAssertEqual(attachment.state, .releasing)

        attachment.reset()
        XCTAssertTrue(host.layer.sublayers?.isEmpty ?? true, "reset removes fading illumination and ripples alike")
        XCTAssertEqual((attachment.presenter.renderer as? CoreAnimationSurfaceRenderer)?.ownedLayerCount, 0)
        XCTAssertEqual(attachment.state, .idle)
        XCTAssertEqual(view.transform, .identity)
    }

    func testCommandObserverSeesEveryCommand() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let attachment = TouchDynamics.attach(to: view)
        var seen: [EngineCommand] = []
        TouchDynamics.commandObserver = { command, a in
            XCTAssertTrue(a === attachment)
            seen.append(command)
        }
        defer { TouchDynamics.commandObserver = nil }
        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0.1))
        XCTAssertEqual(seen.count, 2)
        if case .release(_, let ripple) = seen[1] { XCTAssertTrue(ripple) } else { XCTFail("expected a release") }
    }

    func testRapidRepeatedTapsAreBounded() {
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        var config = TouchDynamicsConfiguration.default
        config.rendering.maximumConcurrentRipples = 2
        let attachment = TouchDynamics.attach(to: view, configuration: config)
        let host = view.subviews.first as! EffectHostView
        for i in 0..<10 {
            let id = TouchIdentifier.test(UInt(i + 1))
            attachment.engine.handle(.began(id: id, location: CGPoint(x: 20, y: 20), time: Double(i)))
            attachment.engine.handle(.ended(id: id, location: CGPoint(x: 20, y: 20), time: Double(i) + 0.05))
        }
        // 2 ripples × 2 layers, plus at most 10 fading illumination layers.
        XCTAssertLessThanOrEqual(host.layer.sublayers?.count ?? 0, 14)
        XCTAssertLessThanOrEqual(attachment.engine.sessions.count, 10)
    }

    func testLeavingTheWindowResetsEffects() {
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        let attachment = TouchDynamics.attach(to: view)
        let host = view.subviews.first as! EffectHostView
        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        XCTAssertEqual(attachment.state, .pressing)

        view.removeFromSuperview() // cell reuse / dismissal
        XCTAssertEqual(attachment.state, .idle)
        XCTAssertTrue(host.layer.sublayers?.isEmpty ?? true)
        XCTAssertEqual(view.transform, .identity)
        XCTAssertNotNil(view.touchDynamicsAttachment, "the attachment survives reuse")

        window.addSubview(view)
        XCTAssertNotNil(window.gestureRecognizers?.first { $0 is TouchObservationGestureRecognizer })
    }

    func testReduceMotionSkipsDeformation() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let attachment = TouchDynamics.attach(to: view)
        attachment.presenter.accessibilityStatusProvider = { AccessibilityStatus(isReduceMotionEnabled: true) }
        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        XCTAssertEqual(view.transform, .identity)
        let host = view.subviews.first as! EffectHostView
        XCTAssertEqual(host.layer.sublayers?.count, 1, "illumination is still shown")
        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0.1))
        let flat = host.layer.sublayers?.last
        XCTAssertFalse(flat is CAGradientLayer, "release is a non-moving flash")
        XCTAssertEqual(flat?.frame, view.bounds)
    }

    func testReduceTransparencyUsesFlatHighlight() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let attachment = TouchDynamics.attach(to: view)
        attachment.presenter.accessibilityStatusProvider = { AccessibilityStatus(isReduceTransparencyEnabled: true) }
        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        let host = view.subviews.first as! EffectHostView
        let layer = host.layer.sublayers!.first!
        XCTAssertFalse(layer is CAGradientLayer)
        XCTAssertEqual(layer.frame, view.bounds)
        XCTAssertNil(host.layer.compositingFilter)
    }

    func testDeformationDriverStepsAsideWhenHostOwnsTheTransform() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let driver = ViewTransformDeformationDriver(view: view)
        let pressed = DeformationState(scaleX: 0.97, scaleY: 0.97, anchor: CGPoint(x: 10, y: 10))
        driver.apply(pressed, animation: .none, completion: nil)
        XCTAssertNotEqual(view.transform, .identity)

        view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5) // the app takes over
        driver.apply(.identity(anchor: CGPoint(x: 10, y: 10)), animation: .none, completion: nil)
        XCTAssertEqual(view.transform, CGAffineTransform(scaleX: 0.5, y: 0.5), "the driver no longer touches the transform")
        driver.reset()
        XCTAssertEqual(view.transform, CGAffineTransform(scaleX: 0.5, y: 0.5))
    }

    func testDeformationComposesWithExistingTransform() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        view.transform = CGAffineTransform(rotationAngle: 0.3)
        let driver = ViewTransformDeformationDriver(view: view)
        driver.apply(DeformationState(scaleX: 0.9, scaleY: 0.9, anchor: CGPoint(x: 100, y: 22)), animation: .none, completion: nil)
        XCTAssertEqual(view.transform.a, 0.9 * cos(0.3), accuracy: 1e-6)
        driver.apply(.identity(anchor: CGPoint(x: 100, y: 22)), animation: .none, completion: nil)
        XCTAssertTrue(view.transform.isApproximatelyEqual(to: CGAffineTransform(rotationAngle: 0.3)))
    }

    func testScrollObserverFindsAncestorScrollViews() {
        let outer = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let inner = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let row = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        outer.addSubview(inner)
        inner.addSubview(row)
        let observer = ScrollTakeoverObserver()
        observer.beginObserving(ancestorsOf: row)
        XCTAssertEqual(observer.observedCount, 2)
        observer.beginObserving(ancestorsOf: row)
        XCTAssertEqual(observer.observedCount, 2, "no duplicate targets")
        observer.endObserving()
        XCTAssertEqual(observer.observedCount, 0)
    }

    func testSwiftUIModifierInstallsASurface() {
        let window = makeWindow()
        let hosting = UIHostingController(rootView: Text("Comment").padding().touchDynamics(.fluid, clipShape: RoundedRectangle(cornerRadius: 8)))
        window.rootViewController = hosting
        hosting.view.frame = window.bounds
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.view.layoutIfNeeded()

        let host = findHost(in: hosting.view)
        XCTAssertNotNil(host, "the representable installs an effect host")
        guard let host, let attachment = host.attachment else { return }
        XCTAssertEqual(attachment.mode, .swiftUI)
        XCTAssertNil(attachment.view)
        XCTAssertFalse(host.isUserInteractionEnabled)
        XCTAssertNil(host.hitTest(CGPoint(x: 1, y: 1), with: nil))
        XCTAssertTrue(attachment.isAttached)
        XCTAssertNotNil(attachment.clipPathProvider)
        XCTAssertNotNil(window.gestureRecognizers?.first { $0 is TouchObservationGestureRecognizer })
        XCTAssertGreaterThan(host.bounds.width, 0)

        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 5, y: 5), time: 0))
        XCTAssertEqual(host.layer.sublayers?.count, 1)
        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 5, y: 5), time: 0.1))
        XCTAssertEqual(attachment.state, .releasing)
    }

    func testMetalRendererFallsBackWhenUnavailable() {
        var config = RenderingConfiguration()
        config.renderer = .metal
        let made = RendererFactory.make(config)
        if MetalSurfaceRenderer.isSupported {
            XCTAssertEqual(made.selection, .metal)
            XCTAssertTrue(made.renderer is MetalSurfaceRenderer)
        } else {
            XCTAssertEqual(made.selection, .coreAnimation)
        }
        XCTAssertEqual(RendererFactory.make(.init()).selection, .coreAnimation)
    }

    func testMetalRendererDrivesEffectsWhenAvailable() throws {
        try XCTSkipUnless(MetalSurfaceRenderer.isSupported, "no Metal device")
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        var config = TouchDynamicsConfiguration.default
        config.rendering.renderer = .metal
        let attachment = TouchDynamics.attach(to: view, configuration: config)
        XCTAssertEqual(attachment.activeRenderer, .metal)
        let host = view.subviews.first as! EffectHostView
        XCTAssertTrue(host.subviews.first is MetalEffectView)
        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        XCTAssertEqual(attachment.state, .pressing)
        XCTAssertFalse(host.subviews.first!.isHidden, "the Metal view shows while live")
        attachment.reset()
        XCTAssertTrue(host.subviews.first!.isHidden, "hidden again when idle")
    }

    func testMetalUniformLayoutMatchesShader() {
        XCTAssertEqual(MemoryLayout<MetalTouch>.stride, 40)
        XCTAssertEqual(MemoryLayout<MetalUniforms>.offset(of: \MetalUniforms.touches), 32)
        XCTAssertEqual(MemoryLayout<MetalUniforms>.stride, 32 + 8 * 40)
        var u = MetalUniforms()
        var t = MetalTouch()
        t.amplitude = 0.5
        u.set(t, at: 3)
        XCTAssertEqual(u.touches.3.amplitude, 0.5)
        XCTAssertEqual(u.touches.2.amplitude, 0)
    }

    func testEffectColorResolution() {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(EffectColor.adaptive.resolve(style: .dark, traits: traits, tint: nil), UIColor.white.cgColor)
        XCTAssertEqual(EffectColor.adaptive.resolve(style: .light, traits: traits, tint: nil), UIColor.black.cgColor)
        XCTAssertEqual(EffectColor.tint.resolve(style: .light, traits: traits, tint: .systemRed), UIColor.systemRed.resolvedColor(with: traits).cgColor)
        XCTAssertEqual(EffectColor.rgba(red: 1, green: 0, blue: 0, alpha: 0.5).resolve(style: .light, traits: traits, tint: nil).alpha, 0.5)
        XCTAssertEqual(EffectColor.color(UIColor.systemBlue), .uiColor(.systemBlue))
        XCTAssertEqual(UIColor.white.cgColor.scaledAlpha(0.25).alpha, 0.25, accuracy: 1e-9)
    }

    func testScrollContentIsTheScrollViewsChild() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 2000))
        let row = UIView(frame: CGRect(x: 0, y: 100, width: 300, height: 44))
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        scrollView.addSubview(content)
        content.addSubview(row)
        row.addSubview(label)
        XCTAssertTrue(TouchDynamicsAttachment.scrollContent(above: label) === content)
        XCTAssertTrue(TouchDynamicsAttachment.scrollContent(above: row) === content)
        XCTAssertNil(TouchDynamicsAttachment.scrollContent(above: UIView()))
        // The content's window-space origin moves with the scroll offset.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(scrollView)
        let before = content.convert(CGPoint.zero, to: nil)
        scrollView.contentOffset = CGPoint(x: 0, y: 120)
        let after = content.convert(CGPoint.zero, to: nil)
        XCTAssertEqual(before.y - after.y, 120, accuracy: 1e-9)
        // A transform on the row does not move the content reference.
        row.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        XCTAssertEqual(content.convert(CGPoint.zero, to: nil), after)
    }

    func testSwiftUIScrollViewAncestryIsReported() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let hosting = UIHostingController(rootView: ScrollView { LazyVStack { ForEach(0..<30) { i in Text("Row \(i)").padding().touchDynamics() } } })
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.frame = window.bounds
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.view.layoutIfNeeded()
        guard let host = findHost(in: hosting.view) else { return XCTFail("no host") }
        var chain: [String] = []
        var scrollViews = 0
        var v: UIView? = host
        while let current = v {
            chain.append(String(describing: type(of: current)))
            if current is UIScrollView { scrollViews += 1 }
            v = current.superview
        }
        print("TD-SCROLLCHAIN uiScrollViews=\(scrollViews) chain=\(chain.joined(separator: " > "))")
        let observer = ScrollTakeoverObserver()
        observer.beginObserving(ancestorsOf: host)
        print("TD-SCROLLCHAIN observedPans=\(observer.observedCount)")
        observer.endObserving()
    }

    private func findHost(in view: UIView) -> EffectHostView? {
        if let host = view as? EffectHostView { return host }
        for sub in view.subviews {
            if let found = findHost(in: sub) { return found }
        }
        return nil
    }
}
#endif

#if canImport(UIKit)
@MainActor
final class SwiftUIHitTestingTests: XCTestCase {
    func testSurfaceNeverBecomesTheHitView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let hosting = UIHostingController(rootView: Text("Comment").padding(40).touchDynamics())
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.frame = window.bounds
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.view.layoutIfNeeded()

        guard let host = findHost(in: hosting.view) else { return XCTFail("no host") }
        let center = host.convert(CGPoint(x: host.bounds.midX, y: host.bounds.midY), to: window)
        let hit = window.hitTest(center, with: nil)
        var chain: [String] = []
        var v: UIView? = hit
        while let current = v {
            chain.append(String(describing: type(of: current)))
            v = current.superview
        }
        print("TD-HITTEST hit=\(String(describing: hit.map { type(of: $0) })) chain=\(chain.joined(separator: " > ")) hostSuperview=\(String(describing: host.superview.map { type(of: $0) })) superInteractive=\(host.superview?.isUserInteractionEnabled ?? false)")
        XCTAssertFalse(hit === host, "the effect host must not be the hit view")
        XCTAssertFalse(hit === host.superview, "SwiftUI's wrapper around the host must not swallow touches")
        XCTAssertTrue(hit === hosting.view || hit?.isDescendant(of: hosting.view) == true)
    }

    func testScrollContentIsTheScrollViewsChild() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 2000))
        let row = UIView(frame: CGRect(x: 0, y: 100, width: 300, height: 44))
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        scrollView.addSubview(content)
        content.addSubview(row)
        row.addSubview(label)
        XCTAssertTrue(TouchDynamicsAttachment.scrollContent(above: label) === content)
        XCTAssertTrue(TouchDynamicsAttachment.scrollContent(above: row) === content)
        XCTAssertNil(TouchDynamicsAttachment.scrollContent(above: UIView()))
        // The content's window-space origin moves with the scroll offset.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(scrollView)
        let before = content.convert(CGPoint.zero, to: nil)
        scrollView.contentOffset = CGPoint(x: 0, y: 120)
        let after = content.convert(CGPoint.zero, to: nil)
        XCTAssertEqual(before.y - after.y, 120, accuracy: 1e-9)
        // A transform on the row does not move the content reference.
        row.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        XCTAssertEqual(content.convert(CGPoint.zero, to: nil), after)
    }

    func testSwiftUIScrollViewAncestryIsReported() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let hosting = UIHostingController(rootView: ScrollView { LazyVStack { ForEach(0..<30) { i in Text("Row \(i)").padding().touchDynamics() } } })
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.frame = window.bounds
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.view.layoutIfNeeded()
        guard let host = findHost(in: hosting.view) else { return XCTFail("no host") }
        var chain: [String] = []
        var scrollViews = 0
        var v: UIView? = host
        while let current = v {
            chain.append(String(describing: type(of: current)))
            if current is UIScrollView { scrollViews += 1 }
            v = current.superview
        }
        print("TD-SCROLLCHAIN uiScrollViews=\(scrollViews) chain=\(chain.joined(separator: " > "))")
        let observer = ScrollTakeoverObserver()
        observer.beginObserving(ancestorsOf: host)
        print("TD-SCROLLCHAIN observedPans=\(observer.observedCount)")
        observer.endObserving()
    }

    private func findHost(in view: UIView) -> EffectHostView? {
        if let host = view as? EffectHostView { return host }
        for sub in view.subviews {
            if let found = findHost(in: sub) { return found }
        }
        return nil
    }
}
#endif
