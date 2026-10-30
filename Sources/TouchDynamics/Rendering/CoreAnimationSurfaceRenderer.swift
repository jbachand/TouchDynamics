#if canImport(UIKit)
import UIKit

/// The default renderer. Everything is a `CAGradientLayer` or flat `CALayer`
/// driven by Core Animation keyframes sampled from the physics models, so the
/// render server does all per-frame work and the main thread is idle while
/// effects play.
@MainActor
final class CoreAnimationSurfaceRenderer: SurfaceRendering {
    private weak var host: EffectHostView?
    private var illuminationLayers: [TouchIdentifier: CALayer] = [:]
    /// Layers fading out after their session ended; owned until removed.
    private var fadingLayers: [CALayer] = []
    /// Wave layers running back to their origin after a re-press.
    private var collapsingLayers: [CALayer] = []
    private var flatLayers: Set<ObjectIdentifier> = []
    private var rippleLayers: [[CALayer]] = []
    private var pool: [CAGradientLayer] = []
    private var generation = 0
    private let maximumRipples: Int
    private let fieldStopCount = 10
    private let waveSampleCount = 30

    init(maximumRipples: Int) {
        self.maximumRipples = max(1, maximumRipples)
    }

    func install(in host: EffectHostView) {
        self.host = host
    }

    func uninstall() {
        reset()
        host = nil
    }

    func hostDidLayout(bounds: CGRect) {
        for layer in illuminationLayers.values where flatLayers.contains(ObjectIdentifier(layer)) {
            layer.frame = bounds
        }
    }

    // MARK: Illumination

    func illuminate(_ session: TouchSession, appearance: ResolvedEffectAppearance, colors: ResolvedEffectColors) {
        guard let host else { return }
        if let stale = illuminationLayers.removeValue(forKey: session.id) {
            discard(stale)
        }
        // A press during the previous lift reverses that lift: the wave
        // collapses back and the fading light comes back under the finger.
        collapseActiveRipples()
        switch appearance.illumination {
        case .none:
            return
        case .flat(let opacity):
            if let adopted = adoptFadingLayer(flat: true) {
                withoutImplicitAnimations {
                    adopted.frame = host.bounds
                    adopted.backgroundColor = colors.illumination.scaledAlpha(opacity)
                }
                illuminationLayers[session.id] = adopted
                rampBack(adopted, duration: appearance.rampInDuration)
                return
            }
            let layer = CALayer()
            layer.frame = host.bounds
            layer.backgroundColor = colors.illumination.scaledAlpha(opacity)
            layer.opacity = 0
            host.layer.addSublayer(layer)
            flatLayers.insert(ObjectIdentifier(layer))
            illuminationLayers[session.id] = layer
            animateOpacity(of: layer, to: 1, duration: appearance.rampInDuration)
        case .field(let field):
            if let adopted = adoptFadingLayer(flat: false) as? CAGradientLayer {
                withoutImplicitAnimations {
                    configureField(adopted, field: field, color: colors.illumination)
                }
                illuminationLayers[session.id] = adopted
                rampBack(adopted, duration: appearance.rampInDuration)
                slide(adopted, to: session.startLocation, duration: appearance.rampInDuration)
                return
            }
            let layer = dequeueGradient()
            configureField(layer, field: field, color: colors.illumination)
            layer.position = session.startLocation
            layer.opacity = 0
            layer.transform = CATransform3DIdentity
            host.layer.addSublayer(layer)
            illuminationLayers[session.id] = layer
            animateOpacity(of: layer, to: 1, duration: appearance.rampInDuration)
        }
    }

    func track(_ session: TouchSession, appearance: ResolvedEffectAppearance) {
        guard let layer = illuminationLayers[session.id] else { return }
        let targetOpacity: Float = session.isInsideBounds ? 1 : 0.35
        if abs(layer.opacity - targetOpacity) > 0.01 {
            animateOpacity(of: layer, to: targetOpacity, duration: 0.12)
        }
        guard !flatLayers.contains(ObjectIdentifier(layer)) else { return }
        guard case .follow(let smoothing) = appearance.tracking else { return }
        let from = layer.presentation()?.position ?? layer.position
        layer.position = session.currentLocation
        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = NSValue(cgPoint: from)
        anim.toValue = NSValue(cgPoint: session.currentLocation)
        anim.duration = max(0.001, smoothing)
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "td.position")
    }

    func emphasize(_ session: TouchSession, appearance: ResolvedEffectAppearance) {
        guard let layer = illuminationLayers[session.id], !flatLayers.contains(ObjectIdentifier(layer)) else { return }
        let scale: CGFloat = 1.12
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        anim.toValue = scale
        anim.duration = 0.3
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        layer.add(anim, forKey: "td.emphasis")
    }

    // MARK: Exit

    func release(
        _ session: TouchSession,
        ripple: Bool,
        appearance: ResolvedEffectAppearance,
        colors: ResolvedEffectColors,
        rippleDidFinish: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let host else {
            rippleDidFinish()
            completion()
            return
        }
        let gen = generation
        var pending = 2
        let done: @MainActor () -> Void = { [weak self] in
            pending -= 1
            guard pending == 0, let self, self.generation == gen else { return }
            completion()
        }

        var exitDuration = appearance.fadeOutDuration
        if ripple, case .wave(_, let duration, _, _, _, _, _) = appearance.release {
            exitDuration = max(exitDuration, duration * 0.55)
        }
        fadeOutIllumination(for: session.id, duration: exitDuration, completion: done)

        guard ripple else {
            rippleDidFinish()
            done()
            return
        }
        switch appearance.release {
        case .none:
            rippleDidFinish()
            done()
        case .staticFade(let duration, let flashOpacity):
            let flash = CALayer()
            flash.frame = host.bounds
            flash.backgroundColor = colors.ripple.scaledAlpha(flashOpacity)
            flash.opacity = 1
            host.layer.addSublayer(flash)
            track(ripple: [flash])
            runTransaction(generation: gen, animations: {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 1
                anim.toValue = 0
                anim.duration = duration
                anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
                anim.fillMode = .forwards
                anim.isRemovedOnCompletion = false
                flash.add(anim, forKey: "td.flash")
            }, completion: { [weak self] in
                self?.untrack(ripple: [flash])
                flash.removeAllAnimations()
                flash.removeFromSuperlayer()
                rippleDidFinish()
                done()
            })
        case .wave(let width, let duration, let decay, let peak, let profile, let expansion, let origin):
            let originPoint = origin == .initialLocation ? session.startLocation : (session.releaseLocation ?? session.currentLocation)
            let coverage: CGFloat
            switch expansion {
            case .fillBounds:
                coverage = RippleWave.coverageRadius(from: originPoint, in: host.bounds)
            case .fixed(let r):
                coverage = r
            case .scaled(let k):
                let base: CGFloat
                if case .field(let f) = appearance.illumination { base = f.radius } else { base = 110 }
                coverage = base * k
            }
            let wave = RippleWave(coverageRadius: coverage, wavefrontWidth: width, duration: duration, decay: decay, peakIntensity: peak, profile: profile)
            let layers = emitWave(wave, at: originPoint, color: colors.ripple, in: host, generation: gen) {
                rippleDidFinish()
                done()
            }
            track(ripple: layers)
        }
    }

    func dissipate(
        _ session: TouchSession,
        immediate: Bool,
        appearance: ResolvedEffectAppearance,
        completion: @escaping @MainActor () -> Void
    ) {
        if immediate {
            if let layer = illuminationLayers.removeValue(forKey: session.id) {
                discard(layer)
            }
            completion()
            return
        }
        fadeOutIllumination(for: session.id, duration: appearance.fadeOutDuration, completion: completion)
    }

    func reset() {
        generation += 1
        for layer in illuminationLayers.values {
            discard(layer)
        }
        illuminationLayers.removeAll()
        for layer in fadingLayers {
            discard(layer)
        }
        fadingLayers.removeAll()
        for layer in collapsingLayers {
            discard(layer)
        }
        collapsingLayers.removeAll()
        for group in rippleLayers {
            for layer in group { discard(layer) }
        }
        rippleLayers.removeAll()
    }

    /// Layers currently owned by the renderer (for tests and diagnostics).
    var ownedLayerCount: Int {
        illuminationLayers.count + fadingLayers.count + collapsingLayers.count + rippleLayers.reduce(0) { $0 + $1.count }
    }

    // MARK: Wave

    private struct WaveLayer {
        let layer: CAGradientLayer
        let locations: CAKeyframeAnimation
        let opacity: CAKeyframeAnimation
    }

    /// Emits the ring and/or disc for `wave` and returns the layers used.
    private func emitWave(
        _ wave: RippleWave,
        at origin: CGPoint,
        color: CGColor,
        in host: EffectHostView,
        generation gen: Int,
        completion: @escaping @MainActor () -> Void
    ) -> [CALayer] {
        let side = wave.travelRadius * 2
        let times = wave.sampleTimes(count: waveSampleCount)
        let keyTimes = times.map { NSNumber(value: $0 / wave.duration) }
        let envelope = times.map { NSNumber(value: Float(wave.envelope(at: $0))) }
        var waveLayers: [WaveLayer] = []

        if wave.profile == .softGradient || wave.profile == .combined {
            let disc = dequeueGradient()
            disc.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            disc.position = origin
            disc.transform = CATransform3DIdentity
            let fill = color.scaledAlpha(0.6 * wave.peakIntensity)
            disc.colors = [fill, fill, color.scaledAlpha(0)]
            let frames: [[NSNumber]] = times.map { t in
                let r = wave.radius(at: t) / wave.travelRadius
                let inner = max(0, (wave.radius(at: t) - wave.wavefrontWidth) / wave.travelRadius)
                return [0, NSNumber(value: Double(min(inner, r))), NSNumber(value: Double(r))]
            }
            waveLayers.append(makeWaveLayer(disc, frames: frames, envelope: envelope, keyTimes: keyTimes, duration: wave.duration))
        }

        if wave.profile == .wavefront || wave.profile == .combined {
            let ring = dequeueGradient()
            ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            ring.position = origin
            ring.transform = CATransform3DIdentity
            let clear = color.scaledAlpha(0)
            let soft = color.scaledAlpha(0.35 * wave.peakIntensity)
            let peak = color.scaledAlpha(wave.peakIntensity)
            ring.colors = [clear, soft, peak, soft, clear]
            let w = wave.wavefrontWidth
            let travel = wave.travelRadius
            let frames: [[NSNumber]] = times.map { t in
                // Spelled-out types: the one-line form times out the type checker.
                let r: CGFloat = wave.radius(at: t)
                let stops: [CGFloat] = [r - 2 * w, r - w, r, r + w, r + 2 * w]
                return stops.map { stop -> NSNumber in
                    let location: CGFloat = (stop / travel).clamped(to: 0...1)
                    return NSNumber(value: Double(location))
                }
            }
            waveLayers.append(makeWaveLayer(ring, frames: frames, envelope: envelope, keyTimes: keyTimes, duration: wave.duration))
        }

        guard !waveLayers.isEmpty else {
            completion()
            return []
        }
        let layers = waveLayers.map { $0.layer as CALayer }
        for item in waveLayers {
            host.layer.addSublayer(item.layer)
        }
        runTransaction(generation: gen, animations: {
            for item in waveLayers {
                item.layer.add(item.locations, forKey: "td.locations")
                item.layer.add(item.opacity, forKey: "td.envelope")
            }
        }, completion: { [weak self] in
            guard let self else { return }
            self.untrack(ripple: layers)
            // A collapsing layer is recycled by its collapse instead.
            for layer in layers where !self.collapsingLayers.contains(where: { $0 === layer }) {
                self.recycle(layer)
            }
            completion()
        })
        return layers
    }

    private func makeWaveLayer(_ layer: CAGradientLayer, frames: [[NSNumber]], envelope: [NSNumber], keyTimes: [NSNumber], duration: TimeInterval) -> WaveLayer {
        let loc = CAKeyframeAnimation(keyPath: "locations")
        loc.values = frames
        loc.keyTimes = keyTimes
        loc.duration = duration
        loc.calculationMode = .linear
        loc.fillMode = .forwards
        loc.isRemovedOnCompletion = false

        let op = CAKeyframeAnimation(keyPath: "opacity")
        op.values = envelope
        op.keyTimes = keyTimes
        op.duration = duration
        op.calculationMode = .linear
        op.fillMode = .forwards
        op.isRemovedOnCompletion = false

        // Model values sit at the end state; the animations carry the motion.
        layer.locations = frames.last
        layer.opacity = 0
        layer.setValue(frames.first, forKey: Self.startLocationsKey)
        return WaveLayer(layer: layer, locations: loc, opacity: op)
    }

    // MARK: Reversal

    private static let startLocationsKey = "td.startLocations"
    private let collapseDuration: TimeInterval = 0.16

    /// The live illumination layer for `id` (tests and diagnostics).
    func illuminationLayer(for id: TouchIdentifier) -> CALayer? {
        illuminationLayers[id]
    }

    /// Takes over the most recent fading illumination layer of the given
    /// kind, cancelling its fade. The fade transaction's completion still
    /// fires (its animation was removed) but no longer discards the layer.
    private func adoptFadingLayer(flat: Bool) -> CALayer? {
        guard let index = fadingLayers.lastIndex(where: { flatLayers.contains(ObjectIdentifier($0)) == flat }) else { return nil }
        let layer = fadingLayers.remove(at: index)
        let presented = layer.presentation()?.opacity ?? layer.opacity
        withoutImplicitAnimations {
            layer.removeAnimation(forKey: "td.fade")
            layer.opacity = presented
        }
        return layer
    }

    /// Brings a fading layer back to full strength from where it is now.
    private func rampBack(_ layer: CALayer, duration: TimeInterval) {
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        let fromScale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        withoutImplicitAnimations {
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
        }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = 1
        opacity.duration = max(0.001, duration)
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(opacity, forKey: "td.opacity")
        if abs(fromScale - 1) > 0.001 {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = fromScale
            scale.toValue = 1
            scale.duration = max(0.001, duration)
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(scale, forKey: "td.emphasis")
        }
    }

    /// Moves an illumination layer to a new finger position.
    private func slide(_ layer: CALayer, to position: CGPoint, duration: TimeInterval) {
        let from = layer.presentation()?.position ?? layer.position
        withoutImplicitAnimations { layer.position = position }
        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = NSValue(cgPoint: from)
        anim.toValue = NSValue(cgPoint: position)
        anim.duration = max(0.001, duration)
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "td.position")
    }

    /// Runs every in-flight wave backwards to its origin and fades it out.
    ///
    /// The running keyframe animations are replaced, not layered over: Core
    /// Animation keeps playing an earlier animation on the same key path, so
    /// the presentation values are captured, the originals removed, and the
    /// collapse animated from there. Removing the originals completes the
    /// wave's transaction, which reports the lift finished and leaves the
    /// collapsing layers to be recycled when the collapse ends.
    private func collapseActiveRipples() {
        let gen = generation
        for group in rippleLayers {
            for layer in group where !collapsingLayers.contains(where: { $0 === layer }) {
                guard let presented = layer.presentation() else {
                    // Never drawn yet: nothing to reverse.
                    layer.removeAnimation(forKey: "td.locations")
                    layer.removeAnimation(forKey: "td.envelope")
                    continue
                }
                let fromOpacity = presented.opacity
                let gradient = layer as? CAGradientLayer
                let fromLocations = (presented as? CAGradientLayer)?.locations ?? gradient?.locations
                let start = gradient?.value(forKey: Self.startLocationsKey) as? [NSNumber]
                collapsingLayers.append(layer)
                withoutImplicitAnimations {
                    layer.removeAnimation(forKey: "td.locations")
                    layer.removeAnimation(forKey: "td.envelope")
                    layer.opacity = 0
                    if let gradient, let start { gradient.locations = start }
                }
                runTransaction(generation: gen, animations: {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = fromOpacity
                    fade.toValue = 0
                    fade.duration = collapseDuration
                    fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    layer.add(fade, forKey: "td.collapseOpacity")
                    if let gradient, let start, let fromLocations {
                        let back = CABasicAnimation(keyPath: "locations")
                        back.fromValue = fromLocations
                        back.toValue = start
                        back.duration = collapseDuration
                        back.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        gradient.add(back, forKey: "td.collapseLocations")
                    }
                }, completion: { [weak self] in
                    guard let self else { return }
                    self.collapsingLayers.removeAll { $0 === layer }
                    self.recycle(layer)
                })
            }
        }
    }

    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: Helpers

    private func configureField(_ layer: CAGradientLayer, field: IlluminationField, color: CGColor) {
        let stops = field.gradientStops(count: fieldStopCount)
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.colors = stops.map { color.scaledAlpha($0.alpha) }
        layer.locations = stops.map { NSNumber(value: Double($0.location)) }
        layer.bounds = CGRect(x: 0, y: 0, width: field.radius * 2, height: field.radius * 2)
    }

    private func fadeOutIllumination(for id: TouchIdentifier, duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        guard let layer = illuminationLayers.removeValue(forKey: id) else {
            completion()
            return
        }
        let gen = generation
        fadingLayers.append(layer)
        runTransaction(generation: gen, animations: {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
            anim.toValue = 0
            anim.duration = max(0.001, duration)
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.opacity = 0
            layer.add(anim, forKey: "td.fade")
        }, completion: { [weak self] in
            guard let self else { return }
            // An adopted layer has left `fadingLayers` and lives on.
            if let index = self.fadingLayers.firstIndex(where: { $0 === layer }) {
                self.fadingLayers.remove(at: index)
                self.discard(layer)
            }
            completion()
        })
    }

    private func animateOpacity(of layer: CALayer, to value: Float, duration: TimeInterval) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = value
        anim.duration = max(0.001, duration)
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = value
        layer.add(anim, forKey: "td.opacity")
    }

    /// Runs `animations` in an explicit transaction and calls `completion` on
    /// the main actor when every animation added inside it has finished or
    /// been removed. Completions from a previous generation are ignored.
    private func runTransaction(generation gen: Int, animations: () -> Void, completion: @escaping @MainActor () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                completion()
            }
        }
        animations()
        CATransaction.commit()
    }

    private func dequeueGradient() -> CAGradientLayer {
        if let layer = pool.popLast() {
            layer.removeAllAnimations()
            layer.opacity = 1
            return layer
        }
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.contentsScale = UIScreen.main.scale
        layer.allowsGroupOpacity = false
        return layer
    }

    private func recycle(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        flatLayers.remove(ObjectIdentifier(layer))
        if let gradient = layer as? CAGradientLayer, pool.count < 8 {
            pool.append(gradient)
        }
    }

    private func discard(_ layer: CALayer) {
        recycle(layer)
    }

    private func track(ripple layers: [CALayer]) {
        rippleLayers.append(layers)
        while rippleLayers.count > maximumRipples {
            let oldest = rippleLayers.removeFirst()
            for layer in oldest { discard(layer) }
        }
    }

    private func untrack(ripple layers: [CALayer]) {
        rippleLayers.removeAll { group in
            group.count == layers.count && zip(group, layers).allSatisfy { $0 === $1 }
        }
    }
}
#endif
