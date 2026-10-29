import XCTest
@testable import TouchDynamics

@MainActor
final class TouchInteractionEngineTests: XCTestCase {
    func testTapIlluminatesThenReleasesWithRipple() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 10))

        XCTAssertEqual(engine.state, .pressing)
        XCTAssertEqual(rec.illuminates.count, 1)
        XCTAssertEqual(rec.illuminates[0].startLocation, CGPoint(x: 50, y: 20))
        XCTAssertEqual(rec.illuminates[0].phase, .pressing)

        engine.handle(.ended(id: id, location: CGPoint(x: 52, y: 21), time: 10.12))
        XCTAssertEqual(engine.state, .releasing)
        XCTAssertEqual(rec.releases.count, 1)
        XCTAssertTrue(rec.releases[0].1, "a tap ripples")
        XCTAssertEqual(rec.releases[0].0.releaseLocation, CGPoint(x: 52, y: 21))
        XCTAssertEqual(rec.releases[0].0.elapsedTime, 0.12, accuracy: 1e-9)

        engine.rippleDidFinish(id)
        XCTAssertEqual(engine.state, .settling)
        engine.effectDidSettle(id)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(engine.sessions.isEmpty)
    }

    func testMovementWithinSlopStaysPressingAndTracks() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 55, y: 22), time: 0.02))
        XCTAssertEqual(engine.state, .pressing)
        XCTAssertEqual(rec.tracks.count, 1)
        XCTAssertEqual(rec.tracks[0].phase, .pressing)
        XCTAssertEqual(rec.tracks[0].currentLocation, CGPoint(x: 55, y: 22))
    }

    func testDragBeyondSlopBecomesTrackingAndRipplesOnReleaseByDefault() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 80, y: 20), time: 0.05))
        XCTAssertEqual(engine.state, .tracking)
        XCTAssertEqual(rec.tracks.last?.phase, .tracking)

        engine.handle(.ended(id: id, location: CGPoint(x: 80, y: 20), time: 0.2))
        XCTAssertEqual(rec.releases.count, 1)
        XCTAssertTrue(rec.releases[0].1)
    }

    func testReleaseAfterDragCanDissipateInstead() {
        var config = GestureConfiguration()
        config.releaseAfterDrag = .dissipate
        let (engine, rec) = makeEngine(configuration: config)
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 80, y: 20), time: 0.05))
        engine.handle(.ended(id: id, location: CGPoint(x: 80, y: 20), time: 0.2))
        XCTAssertEqual(rec.releases.count, 1)
        XCTAssertFalse(rec.releases[0].1, "release after a drag does not ripple")
    }

    func testDragBehaviorDissipateCancelsOnDrag() {
        var config = GestureConfiguration()
        config.dragBehavior = .dissipate
        let (engine, rec) = makeEngine(configuration: config)
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 80, y: 20), time: 0.05))
        XCTAssertEqual(rec.dissipates.count, 1)
        XCTAssertFalse(rec.dissipates[0].1)
        XCTAssertEqual(engine.session(for: id)?.phase, .cancelled)
        XCTAssertEqual(engine.state, .settling)

        // Lifting afterwards emits nothing more.
        engine.handle(.ended(id: id, location: CGPoint(x: 80, y: 20), time: 0.2))
        XCTAssertEqual(rec.releases.count, 0)
        XCTAssertEqual(rec.dissipates.count, 1)
    }

    func testReleaseOutsideBoundsDissipatesWithoutRipple() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 400, y: 20), time: 0.1))
        XCTAssertEqual(rec.tracks.last?.isInsideBounds, false)
        engine.handle(.ended(id: id, location: CGPoint(x: 400, y: 20), time: 0.2))
        XCTAssertEqual(rec.releases.count, 0)
        XCTAssertEqual(rec.dissipates.count, 1)
    }

    func testExitMarginKeepsNearbyReleasesInside() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.ended(id: id, location: CGPoint(x: 50, y: 90), time: 0.2)) // 30 pt below a 60 pt tall surface
        XCTAssertEqual(rec.releases.count, 1)
    }

    func testSystemCancellationDissipates() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.cancelled(id: id, time: 0.1))
        XCTAssertEqual(rec.dissipates.count, 1)
        XCTAssertFalse(rec.dissipates[0].1)
        XCTAssertEqual(engine.state, .settling)
    }

    func testSuppressCancellationIsImmediate() {
        var config = GestureConfiguration()
        config.cancellation = .suppress
        let (engine, rec) = makeEngine(configuration: config)
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.cancelled(id: id, time: 0.1))
        XCTAssertEqual(rec.dissipates.first?.1, true)
    }

    func testScrollTakeoverMaintainsTheEffectByDefault() {
        let (engine, rec) = makeEngine()
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 50, y: 24), time: 0.05))
        engine.scrollDidBegin(at: 0.1)

        XCTAssertTrue(rec.dissipates.isEmpty, "the effect stays alive")
        XCTAssertEqual(engine.session(for: id)?.phase, .pressing)
        XCTAssertEqual(engine.session(for: id)?.didScroll, true)
        XCTAssertEqual(engine.state, .pressing)

        // The finger keeps being tracked while the content scrolls with it.
        engine.handle(.moved(id: id, location: CGPoint(x: 51, y: 22), time: 0.2))
        XCTAssertEqual(rec.tracks.last?.currentLocation, CGPoint(x: 51, y: 22))

        // A second finger during the scroll lights up too.
        let id2 = TouchIdentifier.test(2)
        engine.handle(.began(id: id2, location: CGPoint(x: 120, y: 20), time: 0.3))
        XCTAssertEqual(rec.illuminates.count, 2)
        XCTAssertEqual(engine.session(for: id2)?.didScroll, true)

        // Lifting after a scroll ripples by default.
        engine.handle(.ended(id: id, location: CGPoint(x: 51, y: 22), time: 0.5))
        XCTAssertEqual(rec.releases.count, 1)
        XCTAssertTrue(rec.releases[0].1, "ripple after a scroll")
        XCTAssertEqual(rec.releases[0].0.didScroll, true)
        XCTAssertEqual(engine.session(for: id)?.phase, .releasing)
    }

    func testReleaseAfterScrollCanDissipate() {
        var config = GestureConfiguration()
        config.releaseAfterScroll = .dissipate
        let (engine, rec) = makeEngine(configuration: config)
        engine.handle(.began(id: .test(1), location: CGPoint(x: 50, y: 20), time: 0))
        engine.scrollDidBegin(at: 0.1)
        engine.handle(.ended(id: .test(1), location: CGPoint(x: 50, y: 20), time: 0.5))
        XCTAssertEqual(rec.releases.first?.1, false)
    }

    func testMaintainedScrollReleaseOutsideBoundsDissipates() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: CGPoint(x: 50, y: 20), time: 0))
        engine.scrollDidBegin(at: 0.1)
        engine.handle(.ended(id: .test(1), location: CGPoint(x: 50, y: 400), time: 0.5))
        XCTAssertEqual(rec.releases.count, 0)
        XCTAssertEqual(rec.dissipates.count, 1)
    }

    func testScrollTakeoverDissipatesAndSuppressesNewTouches() {
        var config = GestureConfiguration()
        config.scrollTakeover = .dissipate
        let (engine, rec) = makeEngine(configuration: config)
        let id = TouchIdentifier.test(1)
        engine.handle(.began(id: id, location: CGPoint(x: 50, y: 20), time: 0))
        engine.handle(.moved(id: id, location: CGPoint(x: 50, y: 26), time: 0.03))
        engine.scrollDidBegin(at: 0.04)

        XCTAssertEqual(rec.dissipates.count, 1)
        XCTAssertEqual(engine.session(for: id)?.phase, .scrolling)
        XCTAssertEqual(engine.state, .scrolling)
        XCTAssertTrue(engine.isScrolling)

        // Renderer completion must not drop a scrolling session while the finger is down.
        engine.effectDidSettle(id)
        XCTAssertNotNil(engine.session(for: id))

        // A second finger during the scroll shows nothing.
        let id2 = TouchIdentifier.test(2)
        engine.handle(.began(id: id2, location: CGPoint(x: 100, y: 20), time: 0.1))
        XCTAssertEqual(rec.illuminates.count, 1)
        XCTAssertEqual(engine.session(for: id2)?.phase, .scrolling)

        engine.handle(.ended(id: id, location: CGPoint(x: 50, y: 200), time: 0.5))
        engine.handle(.ended(id: id2, location: CGPoint(x: 100, y: 200), time: 0.5))
        XCTAssertEqual(rec.releases.count, 0)
        XCTAssertTrue(engine.sessions.isEmpty)
        XCTAssertEqual(engine.state, .idle)

        engine.scrollDidEnd()
        XCTAssertFalse(engine.isScrolling)
    }

    func testScrollStateClearsWhenNoFingersRemain() {
        // Hold, scroll, lift. The pan's end notification never arrives because
        // observation stopped at touch-up; the next finger must still light.
        var config = GestureConfiguration()
        config.scrollTakeover = .dissipate
        let (engine, rec) = makeEngine(configuration: config)
        engine.handle(.began(id: .test(1), location: CGPoint(x: 50, y: 20), time: 0))
        engine.scrollDidBegin(at: 0.8)
        engine.handle(.moved(id: .test(1), location: CGPoint(x: 50, y: -200), time: 1.0))
        engine.handle(.ended(id: .test(1), location: CGPoint(x: 50, y: -250), time: 1.2))
        XCTAssertTrue(engine.sessions.isEmpty)
        XCTAssertTrue(engine.isScrolling, "no scrollDidEnd was delivered")

        engine.handle(.began(id: .test(2), location: CGPoint(x: 60, y: 20), time: 2))
        XCTAssertEqual(rec.illuminates.count, 2, "a fresh finger after the scroll finger lifted illuminates")
        XCTAssertEqual(engine.session(for: .test(2))?.phase, .pressing)
        XCTAssertFalse(engine.isScrolling)
        engine.handle(.ended(id: .test(2), location: CGPoint(x: 60, y: 20), time: 2.1))
        XCTAssertEqual(rec.releases.count, 1)
    }

    func testSecondFingerDuringLiveScrollStaysDark() {
        var config = GestureConfiguration()
        config.scrollTakeover = .dissipate
        let (engine, rec) = makeEngine(configuration: config)
        engine.handle(.began(id: .test(1), location: CGPoint(x: 50, y: 20), time: 0))
        engine.scrollDidBegin(at: 0.5)
        engine.handle(.began(id: .test(2), location: CGPoint(x: 90, y: 20), time: 0.6))
        XCTAssertEqual(rec.illuminates.count, 1)
        XCTAssertTrue(engine.isScrolling, "the first finger is still scrolling")
    }

    func testScrollTakeoverCanSuppressImmediately() {
        var config = GestureConfiguration()
        config.scrollTakeover = .suppress
        let (engine, rec) = makeEngine(configuration: config)
        engine.handle(.began(id: .test(1), location: CGPoint(x: 50, y: 20), time: 0))
        engine.scrollDidBegin(at: 0.1)
        XCTAssertEqual(rec.dissipates.first?.1, true)
    }

    func testMultiTouchSessionsAreIndependent() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: CGPoint(x: 20, y: 20), time: 0))
        engine.handle(.began(id: .test(2), location: CGPoint(x: 200, y: 20), time: 0.01))
        XCTAssertEqual(rec.illuminates.count, 2)
        XCTAssertEqual(Set(rec.illuminates.map(\.id)), [.test(1), .test(2)])

        engine.handle(.ended(id: .test(2), location: CGPoint(x: 200, y: 20), time: 0.1))
        XCTAssertEqual(rec.releases.count, 1)
        XCTAssertEqual(rec.releases[0].0.id, .test(2))
        XCTAssertEqual(engine.session(for: .test(1))?.phase, .pressing)
        XCTAssertEqual(engine.state, .pressing, "an active finger outranks a releasing one")
    }

    func testMaximumConcurrentTouchesIsEnforced() {
        var config = GestureConfiguration()
        config.maximumConcurrentTouches = 2
        let (engine, rec) = makeEngine(configuration: config)
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.handle(.began(id: .test(2), location: .zero, time: 0))
        engine.handle(.began(id: .test(3), location: .zero, time: 0))
        XCTAssertEqual(rec.illuminates.count, 2)
        XCTAssertNil(engine.session(for: .test(3)))
        // Moves for an unknown touch are ignored.
        engine.handle(.moved(id: .test(3), location: CGPoint(x: 10, y: 10), time: 0.1))
        XCTAssertEqual(rec.tracks.count, 0)
    }

    func testDuplicateBeganIsIgnored() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.handle(.began(id: .test(1), location: CGPoint(x: 5, y: 5), time: 0.1))
        XCTAssertEqual(rec.illuminates.count, 1)
        XCTAssertEqual(engine.sessions.count, 1)
    }

    func testResetClearsSessionsAndEmitsReset() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.scrollDidBegin()
        engine.reset()
        XCTAssertEqual(rec.resets, 1)
        XCTAssertTrue(engine.sessions.isEmpty)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.isScrolling)
    }

    func testDetachStopsProcessing() {
        let (engine, rec) = makeEngine()
        engine.detach()
        XCTAssertEqual(engine.state, .detached)
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.scrollDidBegin()
        engine.tick(now: 10)
        XCTAssertEqual(rec.illuminates.count, 0)
        XCTAssertEqual(engine.state, .detached)
    }

    func testLongPressPromotionHappensOnce() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.tick(now: 0.3)
        XCTAssertEqual(rec.longPresses.count, 0)
        engine.tick(now: 0.6)
        XCTAssertEqual(rec.longPresses.count, 1)
        XCTAssertTrue(rec.longPresses[0].isLongPress)
        XCTAssertEqual(rec.longPresses[0].elapsedTime, 0.6, accuracy: 1e-9)
        engine.tick(now: 1.0)
        XCTAssertEqual(rec.longPresses.count, 1)
        XCTAssertEqual(engine.session(for: .test(1))?.isLongPress, true)
    }

    func testLongPressDoesNotFireAfterDrag() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.handle(.moved(id: .test(1), location: CGPoint(x: 40, y: 0), time: 0.1))
        engine.tick(now: 1.0)
        XCTAssertEqual(rec.longPresses.count, 0)
    }

    func testSettleTimeoutPrunesStaleSessions() {
        let (engine, _) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.handle(.ended(id: .test(1), location: .zero, time: 1))
        XCTAssertEqual(engine.state, .releasing)
        engine.tick(now: 1 + engine.settleTimeout - 0.1)
        XCTAssertEqual(engine.state, .releasing)
        engine.tick(now: 1 + engine.settleTimeout + 0.1)
        XCTAssertEqual(engine.state, .idle)
    }

    func testVelocityIsEstimatedFromMovement() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.handle(.moved(id: .test(1), location: CGPoint(x: 10, y: 0), time: 0.01))
        let v = rec.tracks.last!.velocity
        XCTAssertEqual(v.dx, 600, accuracy: 1e-6) // 0.6 × 1000 pt/s
        XCTAssertEqual(v.dy, 0, accuracy: 1e-6)
    }

    func testEventsAfterReleaseDoNotEmit() {
        let (engine, rec) = makeEngine()
        engine.handle(.began(id: .test(1), location: .zero, time: 0))
        engine.handle(.ended(id: .test(1), location: .zero, time: 0.1))
        let count = rec.commands.count
        engine.handle(.moved(id: .test(1), location: CGPoint(x: 30, y: 0), time: 0.2))
        engine.handle(.ended(id: .test(1), location: CGPoint(x: 30, y: 0), time: 0.3))
        engine.handle(.cancelled(id: .test(1), time: 0.4))
        XCTAssertEqual(rec.commands.count, count)
    }

    func testEmptyBoundsDisablesInsideCheck() {
        let (engine, rec) = makeEngine(bounds: .zero)
        engine.handle(.began(id: .test(1), location: CGPoint(x: 5000, y: 5000), time: 0))
        engine.handle(.ended(id: .test(1), location: CGPoint(x: 9000, y: 9000), time: 0.1))
        XCTAssertEqual(rec.releases.count, 1)
    }

    func testPhaseClassification() {
        XCTAssertTrue(TouchPhase.pressing.isActive)
        XCTAssertTrue(TouchPhase.tracking.isActive)
        XCTAssertTrue(TouchPhase.scrolling.isActive)
        XCTAssertTrue(TouchPhase.releasing.isFinishing)
        XCTAssertTrue(TouchPhase.settling.isFinishing)
        XCTAssertTrue(TouchPhase.cancelled.isFinishing)
        XCTAssertFalse(TouchPhase.pressing.isFinishing)
        XCTAssertFalse(TouchPhase.releasing.isActive)
    }
}
