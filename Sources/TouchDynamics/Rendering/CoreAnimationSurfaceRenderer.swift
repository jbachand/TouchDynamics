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
    private var flatLayers: Set<ObjectIdentifier> = []
    /// Emitted waves: travelling, lingering (finished but still reversible),
    /// or collapsing back into the finger.
    private var waves: [WaveRecord] = []
    /// Reduce Motion flashes.
    private var flashes: [CALayer] = []
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
            flash.opacity = 0
            host.layer.addSublayer(flash)
            flashes.append(flash)
            runTransaction(generation: gen, animations: {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 1
                anim.toValue = 0
                anim.duration = duration
                anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
                flash.add(anim, forKey: "td.flash")
            }, completion: { [weak self] in
                self?.flashes.removeAll { $0 === flash }
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
            emitWave(wave, at: originPoint, color: colors.ripple, in: host, generation: gen) {
                rippleDidFinish()
                done()
            }
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
        for record in waves {
            recycle(record)
        }
        waves.removeAll()
        for flash in flashes {
            discard(flash)
        }
        flashes.removeAll()
    }

    /// Finished waves still held for a re-press (for tests and diagnostics).
    var lingeringWaveCount: Int {
        waves.filter { $0.state == .lingering }.count
    }

    /// Layers currently owned by the renderer (for tests and diagnostics).
    var ownedLayerCount: Int {
        illuminationLayers.count + fadingLayers.count + flashes.count + waves.reduce(0) { $0 + $1.layers.count }
    }

    // MARK: Wave

    /// One emitted wave and what it needs to run backwards.
    private final class WaveRecord {
        enum State { case travelling, lingering, collapsing }
        let layers: [CAGradientLayer]
        let startLocations: [[NSNumber]]
        let endLocations: [[NSNumber]]
        /// How long a finished wave stays reversible.
        let linger: TimeInterval
        var state: State = .travelling
        var recycleTask: Task<Void, Never>?

        init(layers: [CAGradientLayer], startLocations: [[NSNumber]], endLocations: [[NSNumber]], linger: TimeInterval) {
            self.layers = layers
            self.startLocations = startLocations
            self.endLocations = endLocations
            self.linger = linger
        }
    }

    private struct WaveLayer {
        let layer: CAGradientLayer
        let frames: [[NSNumber]]
        let locations: CAKeyframeAnimation
        let opacity: CAKeyframeAnimation
    }

    /// Emits the ring and/or disc for `wave`. The wave reports `completion`
    /// when its travel ends, then lingers invisibly for at least 0.6 s so a
    /// re-press within a human double tap can still pull it back.
    private func emitWave(
        _ wave: RippleWave,
        at origin: CGPoint,
        color: CGColor,
        in host: EffectHostView,
        generation gen: Int,
        completion: @escaping @MainActor () -> Void
    ) {
        let side = wave.travelRadius * 2
        let times = wave.sampleTimes(count: waveSampleCount)
        let keyTimes = times.map { NSNumber(value: $0 / wave.duration) }
        let envelope = times.map { NSNumber(value: Float(wave.envelope(at: $0))) }
        var items: [WaveLayer] = []

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
            items.append(makeWaveLayer(disc, frames: frames, envelope: envelope, keyTimes: keyTimes, duration: wave.duration))
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
            items.append(makeWaveLayer(ring, frames: frames, envelope: envelope, keyTimes: keyTimes, duration: wave.duration))
        }

        guard !items.isEmpty else {
            completion()
            return
        }
        while waves.count >= maximumRipples, let oldest = waves.first {
            recycle(oldest)
        }
        let record = WaveRecord(
            layers: items.map { $0.layer },
            startLocations: items.map { $0.frames.first ?? [] },
            endLocations: items.map { $0.frames.last ?? [] },
            linger: max(0.6, wave.duration * 1.5)
        )
        waves.append(record)
        for item in items {
            host.layer.addSublayer(item.layer)
        }
        runTransaction(generation: gen, animations: {
            for item in items {
                item.layer.add(item.locations, forKey: "td.locations")
                item.layer.add(item.opacity, forKey: "td.envelope")
            }
        }, completion: { [weak self] in
            completion()
            guard let self, record.state == .travelling, self.waves.contains(where: { $0 === record }) else { return }
            // Finished: keep it, invisible, so a re-press can pull it back.
            record.state = .lingering
            record.recycleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(record.linger * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.recycle(record)
            }
        })
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
        return WaveLayer(layer: layer, frames: frames, locations: loc, opacity: op)
    }

    private func recycle(_ record: WaveRecord) {
        record.recycleTask?.cancel()
        record.recycleTask = nil
        waves.removeAll { $0 === record }
        for layer in record.layers {
            recycle(layer)
        }
    }

    // MARK: Reversal

    private let collapseDuration: TimeInterval = 0.22

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

    /// Runs every travelling or lingering wave back into the finger.
    ///
    /// Core Animation keeps playing an earlier animation on the same key path,
    /// so the running animations are replaced from their presentation values.
    /// The pull-back brightens toward the wave's launch intensity while it
    /// contracts, so it reads as the wave returning, and vanishes at the
    /// origin under the re-lit illumination.
    private func collapseActiveRipples() {
        let gen = generation
        for record in waves where record.state != .collapsing {
            let wasLingering = record.state == .lingering
            record.recycleTask?.cancel()
            record.recycleTask = nil
            record.state = .collapsing
            var from: [(locations: [NSNumber], opacity: Float)] = []
            withoutImplicitAnimations {
                for (i, layer) in record.layers.enumerated() {
                    let presented = layer.presentation()
                    let locations = wasLingering ? record.endLocations[i] : (presented?.locations ?? record.endLocations[i])
                    let opacity: Float = wasLingering ? 0 : (presented?.opacity ?? 0)
                    from.append((locations, opacity))
                    layer.removeAnimation(forKey: "td.locations")
                    layer.removeAnimation(forKey: "td.envelope")
                    layer.locations = record.startLocations[i]
                    layer.opacity = 0
                }
            }
            let duration = collapseDuration
            runTransaction(generation: gen, animations: {
                for (i, layer) in record.layers.enumerated() {
                    let back = CABasicAnimation(keyPath: "locations")
                    back.fromValue = from[i].locations
                    back.toValue = record.startLocations[i]
                    back.duration = duration
                    back.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    layer.add(back, forKey: "td.collapseLocations")

                    let glow = CAKeyframeAnimation(keyPath: "opacity")
                    glow.values = [NSNumber(value: from[i].opacity), 0.7, 0.45, 0]
                    glow.keyTimes = [0, 0.45, 0.85, 1]
                    glow.duration = duration
                    glow.calculationMode = .linear
                    layer.add(glow, forKey: "td.collapseOpacity")
                }
            }, completion: { [weak self] in
                self?.recycle(record)
            })
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

}
#endif
