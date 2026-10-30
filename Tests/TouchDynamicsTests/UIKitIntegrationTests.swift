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
        // `.fluid` for its combined (disc + ring) wave profile.
        let attachment = TouchDynamics.attach(to: view, configuration: .fluid)
        XCTAssertEqual(attachment.activeRenderer, .coreAnimation)
        let host = view.subviews.first as! EffectHostView

        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        XCTAssertEqual(host.layer.sublayers?.count, 1, "one illumination layer")
        let illumination = host.layer.sublayers!.first as! CAGradientLayer
        XCTAssertEqual(illumination.type, .radial)
        XCTAssertEqual(illumination.position, CGPoint(x: 30, y: 20), "illumination originates at the touch")
        XCTAssertEqual(illumination.bounds.width, TouchDynamicsConfiguration.fluid.illumination.radius * 2)
        XCTAssertNotEqual(view.transform, .identity, "press deformation is applied")
        XCTAssertEqual(host.layer.compositingFilter as? String, "screenBlendMode", "a white light brightens in light appearance")

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

    func testRepressDuringLiftReversesTheLift() {
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        let attachment = TouchDynamics.attach(to: view, configuration: .fluid)
        let host = view.subviews.first as! EffectHostView
        let renderer = attachment.presenter.renderer as! CoreAnimationSurfaceRenderer

        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        let light = renderer.illuminationLayer(for: .test(1))!
        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0.1))
        XCTAssertNotNil(light.animation(forKey: "td.fade"))
        XCTAssertEqual(host.layer.sublayers?.count, 3, "fading light plus disc and ring")
        let waves = host.layer.sublayers!.filter { $0 !== light }

        // Press again before the lift finishes.
        attachment.engine.handle(.began(id: .test(2), location: CGPoint(x: 60, y: 20), time: 0.15))
        XCTAssertEqual(host.layer.sublayers?.count, 3, "no new light; the fading one is adopted")
        let adopted = renderer.illuminationLayer(for: .test(2))
        XCTAssertTrue(adopted === light, "the fading light is the live light again")
        XCTAssertNil(light.animation(forKey: "td.fade"))
        XCTAssertNotNil(light.animation(forKey: "td.opacity"), "ramping back up")
        XCTAssertEqual(light.opacity, 1)
        XCTAssertEqual(light.position, CGPoint(x: 60, y: 20), "slides under the new finger")
        for wave in waves {
            XCTAssertNil(wave.animation(forKey: "td.locations"), "the outward wave animation is gone")
            XCTAssertNil(wave.animation(forKey: "td.envelope"))
        }
        XCTAssertNotEqual(view.transform, .identity, "deformation retargets to the pressed state")
        XCTAssertEqual(attachment.state, .pressing)

        // The superseded lift settles once Core Animation commits the removal
        // of its wave animations.
        let deadline = Date().addingTimeInterval(1.5)
        while attachment.engine.session(for: .test(1)) != nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNil(attachment.engine.session(for: .test(1)), "the old session has settled")
        XCTAssertEqual(attachment.engine.session(for: .test(2))?.phase, .pressing)
        XCTAssertTrue(host.layer.sublayers!.contains { $0 === light })
        // Collapsed waves are recycled when their collapse ends.
        let recycled = Date().addingTimeInterval(1.5)
        while renderer.ownedLayerCount > 1, Date() < recycled {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(renderer.ownedLayerCount, 1, "the collapsed wave was recycled; the adopted light stays")
        XCTAssertEqual(host.layer.sublayers?.count, 1)

        // The second lift works normally.
        attachment.engine.handle(.ended(id: .test(2), location: CGPoint(x: 60, y: 20), time: 0.4))
        XCTAssertEqual(attachment.state, .releasing)
        XCTAssertNotNil(light.animation(forKey: "td.fade"))
    }

    func testFinishedWaveLingersAndCanBePulledBack() {
        let window = makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(view)
        var config = TouchDynamicsConfiguration.fluid
        config.ripple.duration = 0.2
        let attachment = TouchDynamics.attach(to: view, configuration: config)
        let host = view.subviews.first as! EffectHostView
        let renderer = attachment.presenter.renderer as! CoreAnimationSurfaceRenderer

        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0))
        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 30, y: 20), time: 0.1))
        let waves = host.layer.sublayers!.compactMap { $0 as? CAGradientLayer }.filter { $0.bounds.width > 300 }
        XCTAssertEqual(waves.count, 2)

        // Wait for the wave to finish travelling: its layers linger, invisible.
        let finished = Date().addingTimeInterval(2)
        while renderer.lingeringWaveCount == 0, Date() < finished {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(renderer.lingeringWaveCount, 1, "the finished wave lingers")
        XCTAssertTrue(waves.allSatisfy { $0.superlayer != nil }, "lingering layers stay in the tree, invisible")
        XCTAssertEqual(attachment.engine.session(for: .test(1))?.phase, .settling, "the lift reported its ripple done; the spring is still settling")

        // A re-press during the linger pulls it back from the edge.
        attachment.engine.handle(.began(id: .test(2), location: CGPoint(x: 40, y: 20), time: 0.4))
        XCTAssertTrue(waves.allSatisfy { $0.animation(forKey: "td.collapseLocations") != nil })
        let recycled = Date().addingTimeInterval(2)
        while renderer.ownedLayerCount > 1, Date() < recycled {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(renderer.ownedLayerCount, 1, "the pulled-back wave is recycled; the new light stays")
        XCTAssertEqual(renderer.lingeringWaveCount, 0)

        // Without a re-press, a finished wave is recycled on its own after its grace window.
        attachment.engine.handle(.ended(id: .test(2), location: CGPoint(x: 40, y: 20), time: 0.5))
        let gone = Date().addingTimeInterval(3)
        while renderer.ownedLayerCount > 0, Date() < gone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(renderer.ownedLayerCount, 0)
    }

    func testSupersededDeformationReportsDone() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let driver = ViewTransformDeformationDriver(view: view)
        let pressed = DeformationState(scaleX: 0.97, scaleY: 0.97, anchor: CGPoint(x: 30, y: 20))
        driver.apply(pressed, animation: .none, completion: nil)
        var settled = 0
        driver.apply(.identity(anchor: CGPoint(x: 30, y: 20)), animation: .spring(SpringSolver()), completion: { settled += 1 })
        XCTAssertEqual(settled, 0)
        driver.apply(pressed, animation: .easeOut(duration: 0.1), completion: nil)
        XCTAssertEqual(settled, 1, "a new target reports the superseded move done")
        XCTAssertFalse(driver.currentState.isIdentity)
        XCTAssertNotEqual(view.transform, .identity)

        var closureSettled = 0
        let closure = ClosureDeformationDriver { _, _ in }
        closure.apply(.identity, animation: .spring(SpringSolver()), completion: { closureSettled += 1 })
        XCTAssertEqual(closureSettled, 0)
        closure.apply(pressed, animation: .easeOut(duration: 0.1), completion: nil)
        XCTAssertEqual(closureSettled, 1)
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
        XCTAssertLessThan(layer.backgroundColor!.relativeLuminance, 0.5, "the flat highlight is a visible shade in light appearance")
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
        XCTAssertEqual(EffectColor.adaptive.resolve(style: .light, traits: traits, tint: nil), UIColor.white.cgColor, "the default is a light in both appearances")
        XCTAssertEqual(EffectColor.adaptiveInk.resolve(style: .light, traits: traits, tint: nil), UIColor.black.cgColor)
        XCTAssertEqual(EffectColor.adaptiveInk.resolve(style: .dark, traits: traits, tint: nil), UIColor.white.cgColor)
        XCTAssertGreaterThan(UIColor.white.cgColor.relativeLuminance, 0.5)
        XCTAssertLessThan(UIColor.black.cgColor.relativeLuminance, 0.5)
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

#if canImport(UIKit)
@MainActor
final class WaveReversalPresentationTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Polls the render server instead of sleeping fixed amounts: on shared CI
    /// runners the presentation layer can lag the model by well over 100 ms.
    func testCollapsedWaveRunsBackwardsOnTheRenderServer() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.isHidden = false
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        window.addSubview(view)
        let attachment = TouchDynamics.attach(to: view, configuration: .fluid)
        let host = view.subviews.first as! EffectHostView

        attachment.engine.handle(.began(id: .test(1), location: CGPoint(x: 40, y: 40), time: 0))
        attachment.engine.handle(.ended(id: .test(1), location: CGPoint(x: 40, y: 40), time: 0.1))
        let ring = host.layer.sublayers!.compactMap { $0 as? CAGradientLayer }.first { ($0.locations?.count ?? 0) == 5 }!

        // Wait until the wave has visibly travelled.
        var front0 = 0.0
        var opacity0: Float = 0
        let travelDeadline = Date().addingTimeInterval(1.5)
        while Date() < travelDeadline {
            spin(0.01)
            if let p = ring.presentation(), let loc = p.locations, loc.count == 5, loc[2].doubleValue > 0.12 {
                front0 = loc[2].doubleValue
                opacity0 = p.opacity
                break
            }
        }
        print("TD-WAVE before re-press front=\(front0) opacity=\(opacity0)")
        try XCTSkipIf(front0 == 0 || ring.superlayer == nil, "the render server never showed the wave travelling")

        // Re-press during the wave, then wait for the front to run back.
        attachment.engine.handle(.began(id: .test(2), location: CGPoint(x: 60, y: 40), time: 0.25))
        var reversed = false
        var front1 = front0
        var opacity1 = opacity0
        let collapseDeadline = Date().addingTimeInterval(1.0)
        while Date() < collapseDeadline, ring.superlayer != nil {
            spin(0.01)
            guard let p = ring.presentation(), let loc = p.locations, loc.count == 5 else { continue }
            front1 = loc[2].doubleValue
            opacity1 = p.opacity
            if front1 < front0 - 0.03 {
                reversed = true
                break
            }
        }
        print("TD-WAVE mid-collapse front=\(front1) opacity=\(opacity1) reversed=\(reversed)")
        XCTAssertTrue(reversed, "the front runs back toward the origin (front \(front0) → \(front1), opacity \(opacity0) → \(opacity1))")

        // The collapsed wave is recycled when its collapse ends.
        let recycleDeadline = Date().addingTimeInterval(2.0)
        while ring.superlayer != nil, Date() < recycleDeadline {
            spin(0.02)
        }
        print("TD-WAVE after collapse inTree=\(ring.superlayer != nil)")
        XCTAssertNil(ring.superlayer, "the collapsed wave is gone")
    }
}
#endif
