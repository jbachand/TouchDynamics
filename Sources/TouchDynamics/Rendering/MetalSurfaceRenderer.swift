#if canImport(UIKit) && canImport(Metal)
import UIKit
import Metal
import QuartzCore

/// The optional Metal renderer. A single fragment shader evaluates the
/// illumination field `I(r,t)` and the release wave `R(r,t)` for every active
/// touch each frame, so illumination, wavefront and disc are continuous fields
/// rather than layered gradients.
///
/// A display link runs only while at least one effect is live; the renderer
/// has zero idle cost. Shader source is compiled at runtime once per process
/// so the package needs no build-system support for `.metal` files.
@MainActor
final class MetalSurfaceRenderer: SurfaceRendering {
    static let maximumTouches = 8

    private struct Illumination {
        var position: CGPoint
        var targetPosition: CGPoint
        var field: IlluminationField?
        var flatOpacity: CGFloat
        var startTime: TimeInterval
        var rampIn: TimeInterval
        var emphasis: CGFloat = 1
        var fadeStart: TimeInterval?
        var fadeDuration: TimeInterval = 0.2
        var smoothing: TimeInterval
        var completion: (@MainActor () -> Void)?
    }

    private struct Ripple {
        var origin: CGPoint
        var wave: RippleWave
        var startTime: TimeInterval
        var onFinish: @MainActor () -> Void
        /// Set when a new press reverses the wave back to its origin.
        var reverseStart: TimeInterval?
        var reverseRadius: CGFloat = 0
        var reverseEnvelope: CGFloat = 0
        /// `onFinish` has been reported.
        var finished = false
    }

    private let reverseDuration: TimeInterval = 0.22

    private struct Flash {
        var opacity: CGFloat
        var startTime: TimeInterval
        var duration: TimeInterval
        var onFinish: @MainActor () -> Void
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let frameRate: FrameRatePreference
    private let maximumRipples: Int

    private weak var host: EffectHostView?
    private var metalView: MetalEffectView?
    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?

    private var illuminations: [TouchIdentifier: Illumination] = [:]
    private var ripples: [Ripple] = []
    private var flashes: [Flash] = []
    private var color: CGColor = UIColor.white.cgColor
    private var generation = 0

    private static var cachedLibrary: (device: ObjectIdentifier, library: MTLLibrary)?

    /// Returns `nil` when Metal is unavailable or the shader fails to compile.
    init?(frameRate: FrameRatePreference, maximumRipples: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        guard let library = Self.library(for: device) else { return nil }
        guard let vertex = library.makeFunction(name: "td_vertex"), let fragment = library.makeFunction(name: "td_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.frameRate = frameRate
        self.maximumRipples = max(1, maximumRipples)
    }

    /// Whether a Metal device and compiled pipeline are available.
    static var isSupported: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return library(for: device) != nil
    }

    private static func library(for device: MTLDevice) -> MTLLibrary? {
        if let cached = cachedLibrary, cached.device == ObjectIdentifier(device) {
            return cached.library
        }
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        guard let library = try? device.makeLibrary(source: MetalShaderSource.source, options: options) else { return nil }
        cachedLibrary = (ObjectIdentifier(device), library)
        return library
    }

    // MARK: Install

    func install(in host: EffectHostView) {
        self.host = host
        let view = MetalEffectView(frame: host.bounds, device: device)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isHidden = true
        host.addSubview(view)
        metalView = view
    }

    func uninstall() {
        reset()
        metalView?.removeFromSuperview()
        metalView = nil
        host = nil
    }

    func hostDidLayout(bounds: CGRect) {
        metalView?.frame = bounds
        metalView?.updateDrawableSize()
    }

    // MARK: Illumination

    func illuminate(_ session: TouchSession, appearance: ResolvedEffectAppearance, colors: ResolvedEffectColors) {
        color = colors.illumination
        let now = CACurrentMediaTime()
        var smoothing: TimeInterval = 0
        if case .follow(let s) = appearance.tracking { smoothing = s }
        reverseRipples(at: now)
        // A press during the previous lift resumes the fading light from its
        // current strength and slides it under the new finger.
        if let (oldID, old) = illuminations.filter({ $0.value.fadeStart != nil }).max(by: { $0.value.fadeStart! < $1.value.fadeStart! }) {
            illuminations[oldID] = nil
            let remaining = 1 - min(1, (now - old.fadeStart!) / old.fadeDuration)
            var field: IlluminationField?
            var flat: CGFloat = 0
            switch appearance.illumination {
            case .none:
                old.completion?()
                stopDisplayLinkIfIdle()
                return
            case .flat(let opacity):
                flat = opacity
            case .field(let f):
                field = f
            }
            illuminations[session.id] = Illumination(
                position: old.position, targetPosition: session.startLocation, field: field,
                flatOpacity: flat, startTime: now - remaining * appearance.rampInDuration,
                rampIn: appearance.rampInDuration, fadeDuration: appearance.fadeOutDuration, smoothing: smoothing
            )
            old.completion?()
            startDisplayLinkIfNeeded()
            return
        }
        switch appearance.illumination {
        case .none:
            return
        case .flat(let opacity):
            illuminations[session.id] = Illumination(
                position: session.startLocation, targetPosition: session.startLocation, field: nil,
                flatOpacity: opacity, startTime: now, rampIn: appearance.rampInDuration,
                fadeDuration: appearance.fadeOutDuration, smoothing: smoothing
            )
        case .field(let field):
            illuminations[session.id] = Illumination(
                position: session.startLocation, targetPosition: session.startLocation, field: field,
                flatOpacity: 0, startTime: now, rampIn: appearance.rampInDuration,
                fadeDuration: appearance.fadeOutDuration, smoothing: smoothing
            )
        }
        startDisplayLinkIfNeeded()
    }

    func track(_ session: TouchSession, appearance: ResolvedEffectAppearance) {
        guard var record = illuminations[session.id] else { return }
        if case .follow = appearance.tracking, record.field != nil {
            record.targetPosition = session.currentLocation
        }
        illuminations[session.id] = record
    }

    func emphasize(_ session: TouchSession, appearance: ResolvedEffectAppearance) {
        illuminations[session.id]?.emphasis = 1.15
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
        let now = CACurrentMediaTime()
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
        beginFade(for: session.id, duration: exitDuration, at: now, completion: done)

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
            flashes.append(Flash(opacity: flashOpacity, startTime: now, duration: duration) {
                rippleDidFinish()
                done()
            })
        case .wave(let width, let duration, let decay, let peak, let profile, let expansion, let origin):
            let originPoint = origin == .initialLocation ? session.startLocation : (session.releaseLocation ?? session.currentLocation)
            let coverage: CGFloat
            switch expansion {
            case .fillBounds:
                coverage = RippleWave.coverageRadius(from: originPoint, in: host?.bounds ?? .zero)
            case .fixed(let r):
                coverage = r
            case .scaled(let k):
                let base: CGFloat
                if case .field(let f) = appearance.illumination { base = f.radius } else { base = 110 }
                coverage = base * k
            }
            let wave = RippleWave(coverageRadius: coverage, wavefrontWidth: width, duration: duration, decay: decay, peakIntensity: peak, profile: profile)
            ripples.append(Ripple(origin: originPoint, wave: wave, startTime: now) {
                rippleDidFinish()
                done()
            })
            while ripples.count > maximumRipples {
                let dropped = ripples.removeFirst()
                dropped.onFinish()
            }
        }
        startDisplayLinkIfNeeded()
    }

    func dissipate(
        _ session: TouchSession,
        immediate: Bool,
        appearance: ResolvedEffectAppearance,
        completion: @escaping @MainActor () -> Void
    ) {
        if immediate {
            illuminations[session.id] = nil
            completion()
            stopDisplayLinkIfIdle()
            return
        }
        beginFade(for: session.id, duration: appearance.fadeOutDuration, at: CACurrentMediaTime(), completion: completion)
    }

    func reset() {
        generation += 1
        illuminations.removeAll()
        ripples.removeAll()
        flashes.removeAll()
        stopDisplayLink()
        metalView?.clear(using: queue)
        metalView?.isHidden = true
    }

    /// Runs every travelling or lingering wave back into the finger.
    private func reverseRipples(at now: TimeInterval) {
        for i in ripples.indices where ripples[i].reverseStart == nil {
            let t = now - ripples[i].startTime
            let wave = ripples[i].wave
            if t >= wave.duration {
                ripples[i].reverseRadius = wave.travelRadius
                ripples[i].reverseEnvelope = 0
            } else {
                ripples[i].reverseRadius = wave.radius(at: t)
                ripples[i].reverseEnvelope = wave.envelope(at: t)
            }
            ripples[i].reverseStart = now
        }
    }

    /// Opacity of a pull-back: brightens toward the launch intensity while it
    /// contracts, then vanishes at the origin.
    private static func pullbackEnvelope(from start: CGFloat, at u: Double) -> CGFloat {
        let points: [(Double, CGFloat)] = [(0, start), (0.45, 0.7), (0.85, 0.45), (1, 0)]
        for (a, b) in zip(points, points.dropFirst()) where u >= a.0 && u <= b.0 {
            let f = CGFloat((u - a.0) / max(1e-9, b.0 - a.0))
            return a.1 + (b.1 - a.1) * f
        }
        return 0
    }

    private func beginFade(for id: TouchIdentifier, duration: TimeInterval, at now: TimeInterval, completion: @escaping @MainActor () -> Void) {
        guard var record = illuminations[id] else {
            completion()
            return
        }
        record.fadeStart = now
        record.fadeDuration = max(0.001, duration)
        record.completion = completion
        illuminations[id] = record
        startDisplayLinkIfNeeded()
    }

    // MARK: Display link

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        metalView?.isHidden = false
        let proxy = DisplayLinkProxy { [weak self] now, dt in
            self?.step(now: now, dt: dt)
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire(_:)))
        switch frameRate {
        case .maximum:
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        case .standard:
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
    }

    private func stopDisplayLinkIfIdle() {
        guard illuminations.isEmpty, ripples.isEmpty, flashes.isEmpty else { return }
        stopDisplayLink()
        metalView?.clear(using: queue)
        metalView?.isHidden = true
    }

    private func step(now: TimeInterval, dt: TimeInterval) {
        var uniforms = MetalUniforms()
        uniforms.color = Self.components(of: color)
        let size = metalView?.bounds.size ?? .zero
        uniforms.size = SIMD2<Float>(Float(size.width), Float(size.height))

        var finished: [@MainActor () -> Void] = []
        var count = 0

        // Illumination fields.
        for (id, var record) in illuminations {
            // Smooth approach to the finger (exponential, time-based).
            if record.smoothing > 0 {
                let k = 1 - exp(-dt / record.smoothing)
                record.position.x += (record.targetPosition.x - record.position.x) * k
                record.position.y += (record.targetPosition.y - record.position.y) * k
            } else {
                record.position = record.targetPosition
            }
            let ramp = record.rampIn > 0 ? min(1, (now - record.startTime) / record.rampIn) : 1
            var fade = 1.0
            if let start = record.fadeStart {
                fade = 1 - min(1, (now - start) / record.fadeDuration)
                if fade <= 0 {
                    illuminations[id] = nil
                    if let c = record.completion { finished.append(c) }
                    continue
                }
            }
            illuminations[id] = record
            let amplitude = CGFloat(ramp * fade) * record.emphasis
            if let field = record.field {
                guard count < Self.maximumTouches else { continue }
                var t = MetalTouch()
                t.position = SIMD2<Float>(Float(record.position.x), Float(record.position.y))
                t.amplitude = Float(field.intensity * amplitude)
                t.sigma = Float(field.sigma)
                t.radius = Float(field.radius)
                uniforms.set(t, at: count)
                count += 1
            } else {
                uniforms.flatAmplitude += Float(record.flatOpacity * amplitude)
            }
        }

        // Waves: travelling, lingering (finished, invisible, reversible) or
        // pulling back.
        var kept: [Ripple] = []
        for var ripple in ripples {
            let t = now - ripple.startTime
            var env: CGFloat = 0
            var radius: CGFloat = 0
            var visible = false
            if let reverseStart = ripple.reverseStart {
                if !ripple.finished {
                    ripple.finished = true
                    finished.append(ripple.onFinish)
                }
                let u = (now - reverseStart) / reverseDuration
                if u >= 1 { continue }
                radius = ripple.reverseRadius * CGFloat(1 - u)
                env = Self.pullbackEnvelope(from: ripple.reverseEnvelope, at: u)
                visible = true
            } else if t >= ripple.wave.duration {
                if !ripple.finished {
                    ripple.finished = true
                    finished.append(ripple.onFinish)
                }
                if t >= ripple.wave.duration + max(0.6, ripple.wave.duration * 1.5) { continue }
            } else {
                env = ripple.wave.envelope(at: t)
                radius = ripple.wave.radius(at: t)
                visible = true
            }
            if visible, count < Self.maximumTouches {
                var u = MetalTouch()
                u.position = SIMD2<Float>(Float(ripple.origin.x), Float(ripple.origin.y))
                u.ringRadius = Float(radius)
                u.ringWidth = Float(ripple.wave.wavefrontWidth)
                if ripple.wave.profile != .softGradient {
                    u.ringAmplitude = Float(ripple.wave.peakIntensity * env)
                }
                if ripple.wave.profile != .wavefront {
                    u.discAmplitude = Float(0.6 * ripple.wave.peakIntensity * env)
                }
                uniforms.set(u, at: count)
                count += 1
            }
            kept.append(ripple)
        }
        ripples = kept

        // Static flashes (Reduce Motion).
        flashes.removeAll { flash in
            let p = (now - flash.startTime) / flash.duration
            if p >= 1 {
                finished.append(flash.onFinish)
                return true
            }
            let eased = 1 - p * p
            uniforms.flatAmplitude += Float(flash.opacity * eased)
            return false
        }

        uniforms.count = UInt32(count)
        uniforms.flatAmplitude = min(1, uniforms.flatAmplitude)
        metalView?.draw(uniforms: uniforms, pipeline: pipeline, queue: queue)

        for callback in finished { callback() }
        stopDisplayLinkIfIdle()
    }

    private static func components(of color: CGColor) -> SIMD4<Float> {
        let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? color
        let c = rgb.components ?? [1, 1, 1, 1]
        if c.count >= 4 {
            return SIMD4<Float>(Float(c[0]), Float(c[1]), Float(c[2]), Float(c[3]))
        }
        if c.count >= 2 {
            return SIMD4<Float>(Float(c[0]), Float(c[0]), Float(c[0]), Float(c[1]))
        }
        return SIMD4<Float>(1, 1, 1, 1)
    }
}

/// Breaks the display-link retain cycle and keeps the callback on the main actor.
/// Only the timestamps cross the isolation boundary.
@MainActor
private final class DisplayLinkProxy: NSObject {
    private let handler: @MainActor (_ now: TimeInterval, _ dt: TimeInterval) -> Void

    init(handler: @escaping @MainActor (_ now: TimeInterval, _ dt: TimeInterval) -> Void) {
        self.handler = handler
    }

    @objc nonisolated func fire(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = max(0, link.targetTimestamp - link.timestamp)
        MainActor.assumeIsolated {
            handler(now, dt)
        }
    }
}

// MARK: - Uniforms (layout matches MetalShaderSource)

struct MetalTouch {
    var position = SIMD2<Float>(0, 0)
    var amplitude: Float = 0
    var sigma: Float = 1
    var radius: Float = 1
    var ringRadius: Float = 0
    var ringWidth: Float = 1
    var ringAmplitude: Float = 0
    var discAmplitude: Float = 0
    var padding: Float = 0
}

struct MetalUniforms {
    var color = SIMD4<Float>(1, 1, 1, 1)
    var size = SIMD2<Float>(0, 0)
    var count: UInt32 = 0
    var flatAmplitude: Float = 0
    var touches: (MetalTouch, MetalTouch, MetalTouch, MetalTouch, MetalTouch, MetalTouch, MetalTouch, MetalTouch) =
        (MetalTouch(), MetalTouch(), MetalTouch(), MetalTouch(), MetalTouch(), MetalTouch(), MetalTouch(), MetalTouch())

    mutating func set(_ touch: MetalTouch, at index: Int) {
        withUnsafeMutableBytes(of: &touches) { raw in
            let stride = MemoryLayout<MetalTouch>.stride
            raw.baseAddress!.advanced(by: index * stride).storeBytes(of: touch, as: MetalTouch.self)
        }
    }
}

enum MetalShaderSource {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Touch {
        float2 position;
        float amplitude;
        float sigma;
        float radius;
        float ringRadius;
        float ringWidth;
        float ringAmplitude;
        float discAmplitude;
        float padding;
    };

    struct Uniforms {
        float4 color;
        float2 size;
        uint count;
        float flatAmplitude;
        Touch touches[8];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut td_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = (positions[vid] + 1.0) * 0.5;
        out.uv.y = 1.0 - out.uv.y;
        return out;
    }

    fragment float4 td_fragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 p = in.uv * u.size;
        float a = u.flatAmplitude;
        for (uint i = 0; i < u.count; ++i) {
            Touch t = u.touches[i];
            float r = distance(p, t.position);
            if (t.amplitude > 0.0 && r < t.radius) {
                float g = exp(-(r * r) / (2.0 * t.sigma * t.sigma));
                float n = r / t.radius;
                float window = 1.0 - n * n * n * n;
                a += t.amplitude * g * window;
            }
            if (t.ringAmplitude > 0.0) {
                float d = r - t.ringRadius;
                a += t.ringAmplitude * exp(-(d * d) / (2.0 * t.ringWidth * t.ringWidth));
            }
            if (t.discAmplitude > 0.0) {
                float inner = t.ringRadius - t.ringWidth;
                float s = 1.0 - smoothstep(inner, t.ringRadius, r);
                a += t.discAmplitude * s;
            }
        }
        a = clamp(a, 0.0, 1.0) * u.color.a;
        return float4(u.color.rgb * a, a);
    }
    """
}

/// A `CAMetalLayer`-backed view that draws the effect fields.
@MainActor
final class MetalEffectView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    init(frame: CGRect, device: MTLDevice) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.scale
        updateDrawableSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MetalEffectView is created programmatically")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
    }

    func draw(uniforms: MetalUniforms, pipeline: MTLRenderPipelineState, queue: MTLCommandQueue) {
        guard bounds.width > 0, bounds.height > 0, let drawable = metalLayer.nextDrawable() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<MetalUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    func clear(using queue: MTLCommandQueue) {
        guard bounds.width > 0, bounds.height > 0, let drawable = metalLayer.nextDrawable() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
#endif
