# Changelog

All notable changes to TouchDynamics are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-10-30

### Changed
- The default light is now a light in both appearances: `EffectColor.adaptive`
  resolves to white everywhere and `EffectCompositing.adaptive` picks `screen`
  for light colors, so content under the finger gets lighter in light mode
  instead of darker. The former shade is available as
  `EffectColor.adaptiveInk`, and the Reduce Transparency flat highlight uses
  it automatically so it stays visible on white.
- A press grows instead of shrinking: `ElasticityConfiguration.response`
  defaults to `.expand`.
- `.subtle` is now the default preset and the top of a quiet ladder. Two
  quieter levels were added below it: `.faint` and `.whisper`, the latter
  noticeable only if you look for it.

## [1.2.3] - 2026-10-30

### Fixed
- The re-press reversal was invisible at human double-tap speed. A wave was
  only reversible until it had travelled, about 0.4 s, and the pull-back
  faded from whatever faint value was left. A finished wave now stays
  reversible for at least 0.6 s more (about a second after the lift), and the
  pull-back brightens toward the wave's launch intensity as it contracts into
  the finger, so a slow double tap visibly draws the wave back. Core
  Animation and Metal.

## [1.2.2] - 2026-10-29

### Fixed
- Double taps: UIKit reuses the `UITouch` object across the taps of a
  multi-tap sequence, so the second tap carried the identifier of the session
  still releasing from the first and the engine dropped it as a duplicate.
  The window router now assigns a fresh identifier at every touch-down, so
  the second tap reverses the first lift and then releases normally.

## [1.2.1] - 2026-10-29

### Fixed
- The re-press reversal did not actually reverse the wave on the Core
  Animation renderer: a collapse animation added on top of the running
  keyframe animation never took effect, so the wave kept travelling. The
  running animations are now replaced from their presentation values, and a
  test reads the layer's presentation values across a re-press to prove the
  front runs back and the wave fades.

## [1.2.0] - 2026-10-29

### Added
- A press during the previous lift reverses the lift instead of starting
  over: the fading light is adopted, ramps back up and slides under the new
  finger; the wave collapses back to its origin; the spring retargets to the
  pressed state. The superseded lift reports settled immediately so its
  session clears. Core Animation and Metal renderers, UIKit and SwiftUI
  deformation drivers.

### Fixed
- Example UI tests: the hold-then-scroll test now waits for the scroll bounce
  to settle before pressing again and verifies the second press through the
  engine command log, which removes a flake on slow CI runners.

## [1.1.1] - 2026-10-28

### Changed
- `GestureConfiguration.releaseAfterScroll` now defaults to `.ripple`: lifting
  the finger after the content scrolled under it emits the release wave.

### Added
- `TouchDynamics.commandObserver`, a diagnostics hook that sees every engine
  command of every attachment.
- UI test proving that a scroll-then-lift reaches the engine as a release with
  the ripple flag through the real touch path.

## [1.1.0] - 2026-10-28

### Changed
- A scroll no longer drops the effect by default. `GestureConfiguration.scrollTakeover`
  is now a `ScrollTakeoverBehavior` (`.maintain` default, `.dissipate`,
  `.suppress`): under `.maintain` the illumination stays under the finger and
  the deformation holds while the content scrolls; lifting then follows the new
  `releaseAfterScroll` (default `.dissipate`, no ripple). `TouchSession.didScroll`
  records that the content moved. The `.material` preset keeps `.dissipate`.
- Source-breaking for code that assigned a `CancellationBehavior` to
  `scrollTakeover`; replace `.dissipate` / `.suppress` with the same cases of
  `ScrollTakeoverBehavior`.

## [1.0.1] - 2026-10-28

### Fixed
- A hold that turned into a scroll could leave the surface dark: the engine's
  scrolling flag stayed set when the pan's end arrived after the touch-up.
  The attachment now closes the scroll when the last finger lifts, and the
  engine clears a stale flag when a new finger lands with no sessions left.

### Added
- Geometric scroll detection (`GestureConfiguration.scrollDetectionDistance`)
  based on the surface's own movement on screen, for containers that are not
  `UIScrollView`-backed.
- A finger that lands on a dragging or decelerating scroll view shows no
  highlight, matching native behavior.
- Hold-then-scroll UI regression test with luminance sampling.

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
