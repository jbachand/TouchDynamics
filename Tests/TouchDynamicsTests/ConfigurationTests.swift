import XCTest
@testable import TouchDynamics

final class ConfigurationTests: XCTestCase {
    func testDefaultIsFluid() {
        XCTAssertEqual(TouchDynamicsConfiguration.default, .fluid)
    }

    func testPresetsAreDistinct() {
        let presets: [TouchDynamicsConfiguration] = [.subtle, .fluid, .elastic, .material, .rippleOnly]
        for (i, a) in presets.enumerated() {
            for b in presets.dropFirst(i + 1) {
                XCTAssertNotEqual(a, b)
            }
        }
    }

    func testPresetCharacteristics() {
        XCTAssertFalse(TouchDynamicsConfiguration.rippleOnly.elasticity.isEnabled)
        XCTAssertTrue(TouchDynamicsConfiguration.rippleOnly.ripple.isEnabled)
        XCTAssertEqual(TouchDynamicsConfiguration.material.illumination.tracking, .anchored)
        XCTAssertEqual(TouchDynamicsConfiguration.material.gesture.dragBehavior, .dissipate)
        XCTAssertGreaterThan(TouchDynamicsConfiguration.elastic.elasticity.strength, TouchDynamicsConfiguration.fluid.elasticity.strength)
        XCTAssertLessThan(TouchDynamicsConfiguration.subtle.illumination.intensity, TouchDynamicsConfiguration.fluid.illumination.intensity)
        XCTAssertEqual(TouchDynamicsConfiguration.fluid.elasticity.damping, 0.72)
    }

    func testCustomMatchesInitializer() {
        let a = TouchDynamicsConfiguration.custom(illumination: .init(intensity: 0.3), ripple: .init(duration: 0.3))
        let b = TouchDynamicsConfiguration(illumination: .init(intensity: 0.3), ripple: .init(duration: 0.3))
        XCTAssertEqual(a, b)
    }

    func testValuesAreClamped() {
        let ill = IlluminationConfiguration(intensity: 5, radius: -3, falloff: 0)
        XCTAssertEqual(ill.intensity, 1)
        XCTAssertEqual(ill.radius, 1)
        XCTAssertEqual(ill.falloff, 0.05)

        let rip = RippleConfiguration(duration: 0, wavefrontWidth: 0, decay: 0, peakIntensity: 3)
        XCTAssertEqual(rip.duration, 0.05)
        XCTAssertEqual(rip.wavefrontWidth, 1)
        XCTAssertEqual(rip.decay, 0.1)
        XCTAssertEqual(rip.peakIntensity, 1)

        let el = ElasticityConfiguration(strength: 2, maximumDeformation: 1, damping: 0, stiffness: 0, mass: 0)
        XCTAssertEqual(el.strength, 0.5)
        XCTAssertEqual(el.maximumDeformation, 0.5)
        XCTAssertEqual(el.damping, 0.05)
        XCTAssertEqual(el.stiffness, 1)
        XCTAssertEqual(el.mass, 0.01)

        let gesture = GestureConfiguration(tapSlop: -1, longPressDuration: 0, scrollDetectionDistance: -5, maximumConcurrentTouches: 0)
        XCTAssertEqual(gesture.tapSlop, 0)
        XCTAssertEqual(gesture.scrollDetectionDistance, 0)
        XCTAssertEqual(GestureConfiguration().scrollDetectionDistance, 4)
        XCTAssertEqual(gesture.longPressDuration, 0.05)
        XCTAssertEqual(gesture.maximumConcurrentTouches, 1)

        XCTAssertEqual(RenderingConfiguration(maximumConcurrentRipples: 0).maximumConcurrentRipples, 1)
        XCTAssertEqual(AccessibilityConfiguration(reducedTransparencyIntensity: 9).reducedTransparencyIntensity, 1)
    }

    func testOffConfigurations() {
        XCTAssertFalse(IlluminationConfiguration.off.isEnabled)
        XCTAssertFalse(RippleConfiguration.off.isEnabled)
        XCTAssertFalse(ElasticityConfiguration.off.isEnabled)
    }

    func testVersion() {
        XCTAssertEqual(TouchDynamics.version, "1.0.1")
    }

    func testTouchIdentifierFromObjectIsStable() {
        final class Token {}
        let token = Token()
        XCTAssertEqual(TouchIdentifier(object: token), TouchIdentifier(object: token))
        XCTAssertNotEqual(TouchIdentifier(object: token), TouchIdentifier(object: Token()))
    }
}

final class ResolvedEffectAppearanceTests: XCTestCase {
    private let config = TouchDynamicsConfiguration.fluid

    func testPlainResolution() {
        let a = ResolvedEffectAppearance(configuration: config, style: .dark, accessibility: .none)
        guard case .field(let field) = a.illumination else { return XCTFail("expected a field") }
        XCTAssertEqual(field.radius, config.illumination.radius)
        guard case .wave(let width, let duration, _, let peak, let profile, _, _) = a.release else { return XCTFail("expected a wave") }
        XCTAssertEqual(width, config.ripple.wavefrontWidth)
        XCTAssertEqual(duration, config.ripple.duration)
        XCTAssertEqual(peak, min(1, config.illumination.intensity * 1.25), accuracy: 1e-9)
        XCTAssertEqual(profile, .combined)
        XCTAssertNotNil(a.elasticity)
        XCTAssertEqual(a.compositingFilterName, "screenBlendMode")
        XCTAssertFalse(a.isSilent)
    }

    func testAdaptiveCompositingFollowsAppearance() {
        XCTAssertEqual(ResolvedEffectAppearance(configuration: config, style: .light, accessibility: .none).compositingFilterName, "multiplyBlendMode")
        var normal = config
        normal.illumination.compositing = .normal
        XCTAssertNil(ResolvedEffectAppearance(configuration: normal, style: .light, accessibility: .none).compositingFilterName)
        var screen = config
        screen.illumination.compositing = .screen
        XCTAssertEqual(ResolvedEffectAppearance(configuration: screen, style: .light, accessibility: .none).compositingFilterName, "screenBlendMode")
    }

    func testReduceMotionRemovesMotion() {
        let a = ResolvedEffectAppearance(configuration: config, style: .light, accessibility: .init(isReduceMotionEnabled: true))
        XCTAssertTrue(a.isReducedMotion)
        XCTAssertNil(a.elasticity)
        XCTAssertEqual(a.tracking, .anchored)
        guard case .staticFade(let duration, let flash) = a.release else { return XCTFail("expected a static fade") }
        XCTAssertEqual(duration, config.ripple.duration)
        XCTAssertGreaterThan(flash, 0)
        guard case .field = a.illumination else { return XCTFail("illumination stays") }
    }

    func testReduceMotionCanBeSilenced() {
        var c = config
        c.accessibility.reducedMotionBehavior = .none
        let a = ResolvedEffectAppearance(configuration: c, style: .light, accessibility: .init(isReduceMotionEnabled: true))
        XCTAssertTrue(a.isSilent)
    }

    func testReduceMotionCanBeIgnored() {
        var c = config
        c.accessibility.respectsReduceMotion = false
        let a = ResolvedEffectAppearance(configuration: c, style: .light, accessibility: .init(isReduceMotionEnabled: true))
        guard case .wave = a.release else { return XCTFail("expected a wave") }
        XCTAssertNotNil(a.elasticity)
    }

    func testReduceTransparencyUsesFlatHighlight() {
        let a = ResolvedEffectAppearance(configuration: config, style: .light, accessibility: .init(isReduceTransparencyEnabled: true))
        XCTAssertEqual(a.illumination, .flat(opacity: config.accessibility.reducedTransparencyIntensity))
        XCTAssertNil(a.compositingFilterName)
        guard case .staticFade = a.release else { return XCTFail("expected a static fade") }
        XCTAssertNotNil(a.elasticity, "Reduce Transparency alone keeps deformation")
    }

    func testVoiceOverDisablesDeformationOnly() {
        let a = ResolvedEffectAppearance(configuration: config, style: .light, accessibility: .init(isVoiceOverRunning: true))
        XCTAssertNil(a.elasticity)
        guard case .wave = a.release else { return XCTFail("expected a wave") }
        var c = config
        c.accessibility.disablesDeformationForVoiceOver = false
        XCTAssertNotNil(ResolvedEffectAppearance(configuration: c, style: .light, accessibility: .init(isVoiceOverRunning: true)).elasticity)
    }

    func testDisabledFeaturesResolveToNone() {
        var c = config
        c.illumination.isEnabled = false
        c.ripple.isEnabled = false
        c.elasticity.isEnabled = false
        let a = ResolvedEffectAppearance(configuration: c, style: .light, accessibility: .none)
        XCTAssertEqual(a.illumination, .none)
        XCTAssertEqual(a.release, .none)
        XCTAssertNil(a.elasticity)
        XCTAssertTrue(a.isSilent)
    }

    func testRipplePeakOverride() {
        var c = config
        c.ripple.peakIntensity = 0.5
        let a = ResolvedEffectAppearance(configuration: c, style: .light, accessibility: .none)
        guard case .wave(_, _, _, let peak, _, _, _) = a.release else { return XCTFail("expected a wave") }
        XCTAssertEqual(peak, 0.5)
    }
}
