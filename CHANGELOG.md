# Changelog

All notable changes to TouchDynamics are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-28

### Added
- `TouchInteractionEngine`: deterministic per-touch state machine
  (`pressing → tracking → releasing → settling`, with `scrolling`, `cancelled`,
  `detached`), monotonic-clock timing, bounded concurrent sessions.
- Physics models: `SpringSolver` (closed-form damped oscillator),
  `IlluminationField`, `RippleWave`, `DeformationField` / `DeformationState`.
- Configuration: `TouchDynamicsConfiguration` with `Illumination`, `Ripple`,
  `Elasticity`, `Gesture`, `Rendering` and `Accessibility` sub-configurations;
  presets `.subtle`, `.fluid` (default), `.elastic`, `.material`, `.rippleOnly`,
  `.custom(…)`.
- Core Animation renderer (default) and optional Metal renderer with an
  embedded, runtime-compiled shader.
- UIKit: `TouchDynamics.attach(to:configuration:)`, `TouchDynamicsAttachment`
  (`reset()`, `detach()`, live `configuration`), `UIView.touchDynamicsAttachment`,
  cell support via `contentView`, automatic reset when leaving the window.
- SwiftUI: `View.touchDynamics(_:)` and `View.touchDynamics(_:clipShape:)`,
  layout-ignored `GeometryEffect` deformation.
- Window-level non-preventing touch observer and scroll-takeover detection via
  ancestor pan recognizers.
- Reduce Motion, Reduce Transparency and VoiceOver adaptations.
- DocC catalog, example app, test suite, CI workflow.
