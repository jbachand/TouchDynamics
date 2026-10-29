# Rendering

Two renderers, one set of equations.

## Core Animation (default)

Illumination is a radial `CAGradientLayer` whose stops are sampled from
``IlluminationField``. The release wave is a pair of radial gradient layers
(disc and ring) whose `locations` and `opacity` are `CAKeyframeAnimation`s
sampled from ``RippleWave``. Deformation uses `UIViewPropertyAnimator` with
`UISpringTimingParameters` (UIKit) or `interpolatingSpring` (SwiftUI) fed by
``SpringSolver``.

Everything runs in the render server. There is no display link, no per-frame
main-thread work, and no layout pass. Layers are pooled and the number of
simultaneous ripples is bounded by
``RenderingConfiguration/maximumConcurrentRipples``.

## Metal (optional)

Set ``RenderingConfiguration/renderer`` to ``RendererSelection/metal``. A
`CAMetalLayer` view is added to the effect surface and a single fragment
shader evaluates, per pixel, the sum of every live illumination field, ring and
disc from the same models. A display link (120 Hz on ProMotion when
``FrameRatePreference/maximum``) runs only while effects are live. The shader
is compiled from source once per process; when Metal is unavailable the
attachment falls back to Core Animation and reports it through
``TouchDynamicsAttachment/activeRenderer``.

`.automatic` currently always selects Core Animation: it is compositor-driven
and visually equivalent for these effects. Metal is there for continuous
multi-touch fields and future shader-based displacement.

## Compositing

The effect surface's layer uses a Core Image blend mode when
``IlluminationConfiguration/compositing`` is ``EffectCompositing/adaptive``
(the default): `multiply` in light appearance, `screen` in dark. An effect
placed above content then reads as lighting the surface beneath the text.
``EffectCompositing/normal`` is plain alpha compositing.

## Performance budget

- Touch feedback onset: the same frame the touch is delivered.
- Steady state: zero CPU; no active display link in Core Animation mode.
- Memory: layers pooled (8), ripples bounded (default 6), sessions bounded
  (default 5), no retained detached views (the host view owns the attachment;
  the attachment holds the target weakly).

Measure on devices with Instruments' Core Animation and Time Profiler
templates; the example app's Tuning tab exposes every knob.
