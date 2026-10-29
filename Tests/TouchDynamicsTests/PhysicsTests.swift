import XCTest
@testable import TouchDynamics

final class SpringSolverTests: XCTestCase {
    func testCriticallyDampedConvergesWithoutOvershoot() {
        let spring = SpringSolver(mass: 1, stiffness: 300, dampingRatio: 1)
        var previous = 1.0
        for i in 1...200 {
            let t = Double(i) / 100
            let x = spring.displacement(at: t, initialDisplacement: 1)
            XCTAssertGreaterThanOrEqual(x, -1e-12, "no overshoot at t=\(t)")
            XCTAssertLessThanOrEqual(x, previous + 1e-12, "monotonic at t=\(t)")
            previous = x
        }
        XCTAssertEqual(spring.value(at: 2, from: 1, to: 0), 0, accuracy: 1e-6)
    }

    func testUnderdampedOvershoots() {
        let spring = SpringSolver(mass: 1, stiffness: 300, dampingRatio: 0.3)
        let samples = (1...300).map { spring.displacement(at: Double($0) / 100, initialDisplacement: 1) }
        XCTAssertTrue(samples.contains { $0 < -0.01 }, "an underdamped spring crosses rest")
        XCTAssertEqual(samples.last!, 0, accuracy: 1e-3)
    }

    func testOverdampedNeverOvershoots() {
        let spring = SpringSolver(mass: 1, stiffness: 300, dampingRatio: 1.6)
        for i in 1...300 {
            XCTAssertGreaterThanOrEqual(spring.displacement(at: Double(i) / 100, initialDisplacement: 1), -1e-12)
        }
        XCTAssertEqual(spring.displacement(at: 3, initialDisplacement: 1), 0, accuracy: 1e-3)
    }

    func testInitialConditionsAreHonored() {
        let spring = SpringSolver(mass: 1, stiffness: 200, dampingRatio: 0.72)
        XCTAssertEqual(spring.displacement(at: 0, initialDisplacement: 0.4, initialVelocity: 3), 0.4)
        let tiny = spring.displacement(at: 1e-4, initialDisplacement: 0.4, initialVelocity: 3)
        XCTAssertEqual(tiny, 0.4 + 3 * 1e-4, accuracy: 1e-5)
    }

    func testDampingCoefficientMatchesUIKitConvention() {
        let spring = SpringSolver(mass: 1, stiffness: 100, dampingRatio: 0.5)
        XCTAssertEqual(spring.dampingCoefficient, 10, accuracy: 1e-9)
        XCTAssertEqual(spring.undampedAngularFrequency, 10, accuracy: 1e-9)
    }

    func testSettlingDurationIsFiniteAndLongerForLessDamping() {
        let tight = SpringSolver(mass: 1, stiffness: 320, dampingRatio: 0.72)
        let loose = SpringSolver(mass: 1, stiffness: 320, dampingRatio: 0.3)
        let a = tight.settlingDuration()
        let b = loose.settlingDuration()
        XCTAssertGreaterThan(a, 0)
        XCTAssertLessThanOrEqual(a, 5)
        XCTAssertGreaterThan(b, a)
        XCTAssertEqual(tight.settlingDuration(initialDisplacement: 0), 0)
        XCTAssertLessThan(abs(tight.displacement(at: a, initialDisplacement: 1)), 0.002)
    }

    func testElasticityConfigurationExposesItsSpring() {
        let config = ElasticityConfiguration(damping: 0.6, stiffness: 250, mass: 2)
        XCTAssertEqual(config.spring, SpringSolver(mass: 2, stiffness: 250, dampingRatio: 0.6))
    }
}

final class IlluminationFieldTests: XCTestCase {
    func testPeakAtCenterAndZeroAtEdge() {
        let field = IlluminationField(radius: 100, falloff: 0.45, intensity: 0.2)
        XCTAssertEqual(field.intensity(atDistance: 0), 0.2, accuracy: 1e-9)
        XCTAssertEqual(field.intensity(atDistance: 100), 0)
        XCTAssertEqual(field.intensity(atDistance: 150), 0)
        XCTAssertEqual(field.sigma, 45, accuracy: 1e-9)
    }

    func testFalloffIsMonotonic() {
        let field = IlluminationField(radius: 100, falloff: 0.45, intensity: 0.2)
        var previous = field.intensity(atDistance: 0)
        for r in stride(from: 1.0, through: 100.0, by: 1.0) {
            let value = field.intensity(atDistance: CGFloat(r))
            XCTAssertLessThanOrEqual(value, previous + 1e-12)
            previous = value
        }
    }

    func testGaussianShape() {
        let field = IlluminationField(radius: 1000, falloff: 0.5, intensity: 1)
        // Far from the window's influence, the field is a plain Gaussian.
        let expected = exp(-(100.0 * 100.0) / (2 * 500.0 * 500.0)) * (1 - pow(0.1, 4))
        XCTAssertEqual(field.intensity(atDistance: 100), CGFloat(expected), accuracy: 1e-6)
    }

    func testGradientStops() {
        let field = IlluminationField(configuration: IlluminationConfiguration(intensity: 0.16, radius: 110, falloff: 0.45))
        let stops = field.gradientStops(count: 10)
        XCTAssertEqual(stops.count, 10)
        XCTAssertEqual(stops.first!.location, 0)
        XCTAssertEqual(stops.first!.alpha, 0.16, accuracy: 1e-9)
        XCTAssertEqual(stops.last!.location, 1)
        XCTAssertEqual(stops.last!.alpha, 0)
        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThan(a.location, b.location)
            XCTAssertGreaterThanOrEqual(a.alpha, b.alpha)
        }
    }
}

final class RippleWaveTests: XCTestCase {
    func testCoverageRadiusReachesFarthestCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(RippleWave.coverageRadius(from: .zero, in: bounds), hypot(200, 100), accuracy: 1e-9)
        XCTAssertEqual(RippleWave.coverageRadius(from: CGPoint(x: 100, y: 50), in: bounds), hypot(100, 50), accuracy: 1e-9)
        XCTAssertEqual(RippleWave.coverageRadius(from: CGPoint(x: 200, y: 100), in: bounds), hypot(200, 100), accuracy: 1e-9)
    }

    func testFrontTravelsPastTheSurface() {
        let wave = RippleWave(coverageRadius: 200, wavefrontWidth: 20, duration: 0.4, decay: 2.4, peakIntensity: 0.2)
        XCTAssertEqual(wave.radius(at: 0), 0)
        XCTAssertEqual(wave.radius(at: 0.4), 240, accuracy: 1e-9)
        XCTAssertEqual(wave.radius(at: 1), 240, accuracy: 1e-9)
        var previous: CGFloat = 0
        for t in stride(from: 0.0, through: 0.4, by: 0.01) {
            let r = wave.radius(at: t)
            XCTAssertGreaterThanOrEqual(r, previous)
            previous = r
        }
        XCTAssertEqual(wave.speed, 600, accuracy: 1e-9)
    }

    func testEnvelopeRunsFromOneToZero() {
        let wave = RippleWave(coverageRadius: 200, wavefrontWidth: 20, duration: 0.4, decay: 2.4, peakIntensity: 0.2)
        XCTAssertEqual(wave.envelope(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(wave.envelope(at: 0.4), 0, accuracy: 1e-9)
        var previous: CGFloat = 1
        for t in stride(from: 0.0, through: 0.4, by: 0.01) {
            let e = wave.envelope(at: t)
            XCTAssertLessThanOrEqual(e, previous + 1e-12)
            previous = e
        }
    }

    func testRingPeaksOnTheFront() {
        let wave = RippleWave(coverageRadius: 200, wavefrontWidth: 20, duration: 0.4, decay: 2.4, peakIntensity: 0.2)
        let t = 0.1
        let front = wave.radius(at: t)
        XCTAssertEqual(wave.ringIntensity(atDistance: front, time: t), 0.2 * wave.envelope(at: t), accuracy: 1e-9)
        XCTAssertLessThan(wave.ringIntensity(atDistance: front + 40, time: t), wave.ringIntensity(atDistance: front, time: t))
    }

    func testDiscFillsBehindTheFront() {
        let wave = RippleWave(coverageRadius: 200, wavefrontWidth: 20, duration: 0.4, decay: 2.4, peakIntensity: 0.2, profile: .softGradient)
        let t = 0.2
        let front = wave.radius(at: t)
        XCTAssertEqual(wave.discIntensity(atDistance: 0, time: t), 0.12 * wave.envelope(at: t), accuracy: 1e-9)
        XCTAssertEqual(wave.discIntensity(atDistance: front + 1, time: t), 0)
        XCTAssertEqual(wave.intensity(atDistance: 0, time: t), wave.discIntensity(atDistance: 0, time: t))
    }

    func testCombinedIntensityIsBounded() {
        let wave = RippleWave(coverageRadius: 200, wavefrontWidth: 20, duration: 0.4, decay: 2.4, peakIntensity: 1, profile: .combined)
        for t in stride(from: 0.0, through: 0.4, by: 0.05) {
            for r in stride(from: 0.0, through: 240.0, by: 10) {
                XCTAssertLessThanOrEqual(wave.intensity(atDistance: CGFloat(r), time: t), 1)
            }
        }
        let times = wave.sampleTimes(count: 5)
        XCTAssertEqual(times.count, 5)
        for (actual, expected) in zip(times, [0, 0.1, 0.2, 0.3, 0.4]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-12)
        }
    }
}

final class DeformationTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 300, height: 80)

    func testAnchoredScaleKeepsAnchorFixed() {
        let field = DeformationField(configuration: ElasticityConfiguration(strength: 0.03))
        let session = TouchSession(id: .test(1), startLocation: CGPoint(x: 40, y: 20), startTime: 0)
        let state = field.state(for: session, in: bounds)
        XCTAssertEqual(state.anchor, CGPoint(x: 40, y: 20))
        XCTAssertEqual(state.scaleX, 0.97, accuracy: 1e-9)
        XCTAssertEqual(state.scaleY, 0.97, accuracy: 1e-9)

        let topLeft = state.affineTransform(in: bounds, origin: .topLeft)
        let mapped = CGPoint(x: 40, y: 20).applying(topLeft)
        XCTAssertEqual(mapped.x, 40, accuracy: 1e-9)
        XCTAssertEqual(mapped.y, 20, accuracy: 1e-9)
        let far = CGPoint(x: 300, y: 80).applying(topLeft)
        XCTAssertEqual(far.x, 40 + 260 * 0.97, accuracy: 1e-9)

        // The center convention maps the same anchor to itself relative to the center.
        let centered = state.affineTransform(in: bounds, origin: .center)
        let v = CGPoint(x: 40 - 150, y: 20 - 40).applying(centered)
        XCTAssertEqual(v.x, 40 - 150, accuracy: 1e-9)
        XCTAssertEqual(v.y, 20 - 40, accuracy: 1e-9)
    }

    func testUniformScaleAnchorsAtCenter() {
        let field = DeformationField(configuration: ElasticityConfiguration(strength: 0.02, mode: .uniformScale, response: .expand))
        let session = TouchSession(id: .test(1), startLocation: CGPoint(x: 10, y: 10), startTime: 0)
        let state = field.state(for: session, in: bounds)
        XCTAssertEqual(state.anchor, CGPoint(x: 150, y: 40))
        XCTAssertEqual(state.scaleX, 1.02, accuracy: 1e-9)
    }

    func testMaximumDeformationClamps() {
        let field = DeformationField(configuration: ElasticityConfiguration(strength: 0.4, maximumDeformation: 0.05))
        let session = TouchSession(id: .test(1), startLocation: CGPoint(x: 10, y: 10), startTime: 0)
        let state = field.state(for: session, in: bounds)
        XCTAssertEqual(state.scaleX, 0.95, accuracy: 1e-9)
    }

    func testTensionStretchesAlongDisplacement() {
        let field = DeformationField(configuration: ElasticityConfiguration(strength: 0.02, tension: 0.1))
        var session = TouchSession(id: .test(1), startLocation: CGPoint(x: 100, y: 40), startTime: 0)
        let rest = field.state(for: session, in: bounds)
        session.currentLocation = CGPoint(x: 160, y: 40)
        let moved = field.state(for: session, in: bounds)
        XCTAssertGreaterThan(moved.scaleX, rest.scaleX)
        XCTAssertEqual(moved.scaleY, rest.scaleY, accuracy: 1e-9)
        XCTAssertGreaterThan(moved.translation.dx, 0)
        XCTAssertEqual(moved.translation.dy, 0, accuracy: 1e-9)
    }

    func testShearModeShearsWithDisplacement() {
        let field = DeformationField(configuration: ElasticityConfiguration(strength: 0.02, mode: .shear, tension: 0.2))
        var session = TouchSession(id: .test(1), startLocation: CGPoint(x: 100, y: 40), startTime: 0)
        session.currentLocation = CGPoint(x: 100, y: 60)
        let state = field.state(for: session, in: bounds)
        XCTAssertEqual(state.shearX, 0, accuracy: 1e-9)
        XCTAssertEqual(state.shearY, 0.2 * 20 / 80, accuracy: 1e-9)
    }

    func testDisabledOrEmptyBoundsIsIdentity() {
        let disabled = DeformationField(configuration: .off)
        let session = TouchSession(id: .test(1), startLocation: CGPoint(x: 10, y: 10), startTime: 0)
        XCTAssertTrue(disabled.state(for: session, in: bounds).isIdentity)
        let enabled = DeformationField(configuration: .init())
        XCTAssertTrue(enabled.state(for: session, in: .zero).isIdentity)
        XCTAssertTrue(enabled.restingState(for: session, in: bounds).isIdentity)
        XCTAssertEqual(enabled.restingState(for: session, in: bounds).anchor, CGPoint(x: 10, y: 10))
    }

    func testEmphasisDeepensPress() {
        let field = DeformationField(configuration: ElasticityConfiguration(strength: 0.02, maximumDeformation: 0.1))
        let session = TouchSession(id: .test(1), startLocation: CGPoint(x: 10, y: 10), startTime: 0)
        XCTAssertEqual(field.state(for: session, in: bounds, emphasis: 1.5).scaleX, 0.97, accuracy: 1e-9)
    }

    func testIdentityTransformIsIdentity() {
        XCTAssertTrue(DeformationState.identity.isIdentity)
        XCTAssertTrue(DeformationState.identity.affineTransform(in: bounds, origin: .topLeft).isIdentity)
        XCTAssertTrue(DeformationState.identity(anchor: CGPoint(x: 99, y: 9)).affineTransform(in: bounds, origin: .center).isIdentity)
    }
}
