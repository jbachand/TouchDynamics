# Configuring

Every effect is driven by one `Sendable`, `Equatable` value.

## Hierarchy

| Type | Controls |
| --- | --- |
| ``TouchDynamicsConfiguration`` | The whole effect; presets live here |
| ``IlluminationConfiguration`` | Color, intensity, radius, falloff, ramp, tracking, placement, compositing |
| ``RippleConfiguration`` | Duration, expansion, profile, wavefront width, decay, origin, color |
| ``ElasticityConfiguration`` | Strength, mode, response (grow by default), tension, limits, spring (damping, stiffness, mass) |
| ``GestureConfiguration`` | Tap slop, long press, drag, release, scroll, cancellation, touch limits |
| ``RenderingConfiguration`` | Renderer, clip shape, frame rate, ripple limit |
| ``AccessibilityConfiguration`` | Reduce Motion, Reduce Transparency, VoiceOver adaptations |

## Changing configuration live

Set ``TouchDynamicsAttachment/configuration`` (UIKit) or pass a new value to
the modifier (SwiftUI). Changes apply to the next touch; touches in flight
finish with the look they started with. A renderer change takes effect once no
effect is live.

## Source compatibility

All configuration types are `public` structs with memberwise initializers whose
parameters have defaults. New properties will be added with defaults, so
`.init(intensity: 0.2)` call sites keep compiling across minor versions.

## Models

The visual models are public too, so you can plot them, test them, or drive a
custom renderer from the same numbers:

- ``IlluminationField``: `I(r) = A·exp(−r² / 2σ²)` with `σ = falloff·radius`
- ``RippleWave``: `R(r, t) = B·e^(−λt)·exp(−(r − vt)² / 2w²)`
- ``SpringSolver``: `m·ẍ + c·ẋ + k·x = 0`, `c = 2ζ√(km)`
- ``DeformationField``: anchored scale, uniform scale, shear
