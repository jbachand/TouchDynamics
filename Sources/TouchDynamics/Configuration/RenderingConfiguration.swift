import Foundation
import CoreGraphics

/// Which renderer draws the effects.
public enum RendererSelection: Sendable, Equatable {
    /// Core Animation. It is compositor-driven, needs no per-frame CPU work,
    /// and is supported everywhere, so it is the automatic choice.
    case automatic
    /// Force Core Animation.
    case coreAnimation
    /// Metal, when a device is available; falls back to Core Animation otherwise.
    case metal
}

/// Frame-rate preference for renderers that drive their own display link.
public enum FrameRatePreference: Sendable, Equatable {
    /// Up to the display's maximum (120 Hz on ProMotion).
    case maximum
    /// 60 Hz.
    case standard
}

/// The shape the effect surface is clipped to.
public enum EffectClipShape: Sendable, Equatable {
    /// UIKit: mirror the host layer's corner radius and masked corners.
    /// SwiftUI: rectangle, unless a `clipShape:` is passed to the modifier.
    case automatic
    /// No clipping.
    case none
    /// The host bounds.
    case rectangle
    /// A rounded rectangle with a continuous corner curve.
    case roundedRectangle(cornerRadius: CGFloat)
    /// A capsule.
    case capsule
    /// An ellipse inscribed in the bounds.
    case ellipse
}

/// Configuration for rendering.
public struct RenderingConfiguration: Sendable, Equatable {
    /// Renderer selection.
    public var renderer: RendererSelection
    /// Clipping shape for the effect surface.
    public var clipShape: EffectClipShape
    /// Frame-rate preference (Metal renderer only).
    public var preferredFrameRate: FrameRatePreference
    /// Maximum simultaneous ripple animations; the oldest is recycled first.
    public var maximumConcurrentRipples: Int

    public init(
        renderer: RendererSelection = .automatic,
        clipShape: EffectClipShape = .automatic,
        preferredFrameRate: FrameRatePreference = .maximum,
        maximumConcurrentRipples: Int = 6
    ) {
        self.renderer = renderer
        self.clipShape = clipShape
        self.preferredFrameRate = preferredFrameRate
        self.maximumConcurrentRipples = max(1, maximumConcurrentRipples)
    }
}
