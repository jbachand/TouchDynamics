# TouchDynamics

Physically responsive touch feedback for any iOS view, in one line.

- **Touch illumination** — a Gaussian light appears under the finger the frame it lands, and follows it. It is a light in both appearances: what it covers gets lighter.
- **Release ripple** — a soft disc and wavefront ring leave from where the finger lifted and fade as they cover the view.
- **Elastic deformation** — the content grows slightly from the finger and springs back; layout never changes.
- **Interruptible** — a press during the previous lift reverses it: the light comes back under the finger, the wave collapses, the spring retargets.
- **Gesture-safe** — touches are observed, never claimed. Scrolling, swiping, navigation, buttons and cell selection work exactly as before.
- **Universal** — SwiftUI views, UIKit views and controls, table/collection cells, nested scroll containers.
- **Accessible** — Reduce Motion, Reduce Transparency and VoiceOver are respected by default.
- **Lean** — Swift Package, no third-party dependencies, iOS 16+, Swift 5.9+, Swift 6 strict-concurrency clean.

```swift
import TouchDynamics

CommentRow(comment: comment)
    .touchDynamics()
```

```swift
let attachment = TouchDynamics.attach(to: commentView, configuration: .default)
```

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/jbachand/TouchDynamics.git", from: "1.0.0")
```

Then add `TouchDynamics` to your target's dependencies. Xcode: **File ▸ Add Package Dependencies…**

## Usage

### SwiftUI

```swift
// Per item
ScrollView {
    LazyVStack {
        ForEach(comments) { comment in
            CommentRow(comment: comment)
                .touchDynamics()
        }
    }
}

// Clipped to the content's shape
Card()
    .touchDynamics(.elastic, clipShape: RoundedRectangle(cornerRadius: 16))

// Whole container as one surface
ScrollView { … }.touchDynamics(.material)
```

### UIKit

```swift
// Any view or control; no subclassing
TouchDynamics.attach(to: cardView, configuration: .fluid)

// Cells: call from cellForRow; effects reset on reuse automatically
TouchDynamics.attach(to: cell)

// Lifecycle
cardView.touchDynamicsAttachment?.reset()   // cancel effects now
TouchDynamics.detach(from: cardView)        // remove everything
```

### Configuration

```swift
var config = TouchDynamicsConfiguration.fluid
config.illumination = .init(intensity: 0.18, radius: 90)
config.ripple = .init(duration: 0.35, expansion: .fillBounds)
config.elasticity = .init(strength: 0.025, damping: 0.72)

CommentContent().touchDynamics(config)
```

| Type | Controls |
| --- | --- |
| `IlluminationConfiguration` | color, intensity, radius, falloff, ramp-in, fade-out, tracking, placement, compositing |
| `RippleConfiguration` | duration, expansion, profile (disc / ring / both), wavefront width, decay, origin, color |
| `ElasticityConfiguration` | strength, mode (anchored / uniform / shear), expand (default) or compress, directional tension, limits, spring (damping ratio, stiffness, mass) |
| `GestureConfiguration` | tap slop, long press, drag behavior, release-after-drag, scroll takeover (maintain / dissipate / suppress), release-after-scroll, cancellation, touch limit, pointer |
| `RenderingConfiguration` | Core Animation or Metal, clip shape, frame rate, ripple limit |
| `AccessibilityConfiguration` | Reduce Motion, Reduce Transparency, VoiceOver behavior |

### Presets

| Preset | Behavior |
| --- | --- |
| `.whisper` | Barely there: noticeable only if you look for it |
| `.faint` | Noticeably quieter than subtle |
| `.subtle` (= `.default`) | Soft illumination, minimal deformation; the top of the quiet ladder |
| `.fluid` | Bright ripple, gentle directional elasticity — the comment-row interaction the SDK was specified against |
| `.elastic` | Stronger spring and touch deformation |
| `.material` | Soft, diffused, surface-oriented feedback; drag dissipates |
| `.rippleOnly` | Illumination and wave without deformation |
| `.custom(…)` | Fully configurable |

## How it works

```
┌─────────────────────────────────────────────────────────┐
│ Public SDK      SwiftUI modifier · UIKit attachment      │
├─────────────────────────────────────────────────────────┤
│ Touch Interaction Engine                                 │
│   TouchInteractionEngine — deterministic state machine   │
│   idle → pressing → tracking → releasing → settling      │
│   alternates: scrolling · cancelled · detached           │
├─────────────────────────────────────────────────────────┤
│ Physics        SpringSolver · IlluminationField          │
│                RippleWave · DeformationField             │
├───────────────────────────┬─────────────────────────────┤
│ Core Animation (default)  │ Metal (optional)            │
└───────────────────────────┴─────────────────────────────┘
```

**Observation, not recognition.** One gesture recognizer per `UIWindow` overrides `canPrevent`/`canBePrevented` to `false`, never cancels or delays touches, never leaves `.possible` while fingers are down, and decides per touch — in `shouldReceive` — whether a registered surface is under the finger (hit-view ancestry plus geometry; innermost wins). It is the same path for UIKit and SwiftUI, so feedback starts on the same frame the touch lands, even inside scroll views with `delaysContentTouches`.

**Scroll arbitration.** At touch-down the attachment adds a target-action to the `panGestureRecognizer` of every ancestor `UIScrollView`. When a pan begins, the effect rides along by default: the illumination stays under the finger and the deformation holds while the content scrolls, and lifting emits the release ripple (`scrollTakeover: .maintain`, `releaseAfterScroll: .ripple`; use `.dissipate` for a plain fade). Choose `.dissipate` or `.suppress` for the native-highlight behavior where a scroll drops the effect and new fingers stay dark. The surface's own on-screen movement is watched as a second signal for containers that are not `UIScrollView`-backed, and the scroll is closed when the last finger lifts. Nothing about the scroll view changes.

**One set of equations.** `I(r) = A·exp(−r²/2σ²)`, `R(r,t) = B·e^(−λt)·exp(−(r−vt)²/2w²)` and `m·ẍ + c·ẋ + k·x = 0` live in public value types. Core Animation samples them into keyframes; Metal evaluates them per pixel; SwiftUI's `interpolatingSpring` and UIKit's `UISpringTimingParameters` get the same `(mass, stiffness, damping)`.

**Layout-neutral.** UIKit deformation is a `transform` composed over the view's existing transform and restored on settle; SwiftUI deformation is a `GeometryEffect` marked `ignoredByLayout()`. If the host changes the transform during a press, the driver steps aside for that press.

**Zero idle cost.** Core Animation mode has no display link and no per-frame main-thread work. Metal mode runs a display link only while an effect is live. Layers are pooled; ripples and sessions are bounded; the host view owns the attachment and the attachment holds the target weakly.

## Accessibility

| Setting | Behavior |
| --- | --- |
| Reduce Motion | Illumination appears and stays anchored; release is a non-moving cross-fade with a brief flat flash; no deformation. Or no feedback at all via `reducedMotionBehavior = .none`. |
| Reduce Transparency | Flat, higher-contrast highlight over the surface instead of a gradient; no blend mode. |
| VoiceOver | Illumination and ripple remain; deformation is off so the focused element stays stable. |

The effect surface is never an accessibility element and never hit-tests.

## Example app

`Example/TouchDynamicsExample.xcodeproj` (regenerate with `xcodegen` from `Example/project.yml`) demonstrates comments, buttons, cards, UIKit table/collection cells, sheets, navigation pushes, nested scrolling, a container-level surface, and a Tuning tab that edits every configuration value against a live preview.

The demo starts on the `.subtle` preset, the default; the Tuning tab switches presets and edits every value. The `TouchDynamicsExampleUITests` target drives the app with real touches and asserts that every native gesture still works with effects on. Launch arguments `-td-preset <whisper|faint|subtle|fluid|elastic|material|rippleOnly>` pick a preset, `-td-scheme dark|light` forces an appearance, `-td-mode off|silent|noelastic|full` select a baseline without the modifier, the observer with silent effects, effects without deformation, or everything, and `-td-log <path>` records every engine command.

## Acceptance criteria

| Criterion | Status |
| --- | --- |
| One-line SwiftUI integration works without additional setup | `View.touchDynamics()`; covered by `testSwiftUIModifierInstallsASurface` and the example app's UI tests |
| UIKit attachment requires no view subclassing | `TouchDynamics.attach(to:)`; covered by `UIKitIntegrationTests` |
| Ripple originates at the actual touch coordinate | `testEngineCommandsDriveCoreAnimationLayersAndResetClearsThem` asserts layer positions |
| Illumination responds during touch-down | `.illuminate` emitted synchronously on `began`; same-frame delivery via the window observer |
| Release ripple expands and fades smoothly | `RippleWaveTests`: monotonic front, 1→0 envelope, bounded intensity |
| Elastic deformation springs back without layout changes | `DeformationTests`; transform/GeometryEffect only |
| Native scrolling and navigation gestures remain functional | Non-preventing observer; `testWindowObserverIsSharedAndNonExclusive`; scroll takeover tests; `GesturePassThroughUITests` drives real touches on the simulator with effects on: tap, scroll, SwiftUI button, `UIButton` event, table scroll and cell taps, push, interactive pop, sheet |
| Rapid repeated taps and cell reuse leave no stale effects | `testRapidRepeatedTapsAreBounded`, `testLeavingTheWindowResetsEffects` |
| Reduce Motion and VoiceOver are supported | `ResolvedEffectAppearanceTests`, `testReduceMotionSkipsDeformation` |
| Performance meets measured device-specific budgets | Architecture is compositor-driven with zero idle cost; **device measurements are still to be taken** (see Status) |
| Package builds without third-party dependencies | `Package.swift` has none |
| Example app and public API documentation are complete | Example app + DocC catalog in `Sources/TouchDynamics/Documentation.docc` |

## Status and roadmap

This is the v1.0 implementation of the PRD, verified on the iOS Simulator by 103 unit/integration tests and 8 UI tests that exercise the real touch path. Two things are explicitly still open:

- **Device measurement.** Frame-rate and onset budgets must be confirmed on hardware with Instruments, including the oldest supported devices. The architecture is built for it (no display link in the default renderer, bounded resources), but the numbers have not been taken yet.
- **Shader-based displacement.** `DeformationMode.displacement` is accepted and renders as `anchoredScale` on every renderer in v1.0. Content-texture displacement is reserved for the Metal renderer in a later release.

Planned: spatial haptics synchronized to release, localized mesh deformation, macOS pointer interactions, tvOS focus effects, custom shader plug-ins.

## Requirements

iOS 16.0+, Swift 5.9+, Xcode 15+. The platform-neutral core (engine, physics, configuration) also builds on macOS 13+ so `swift build` works on a Mac host; rendering and integration are iOS-only.

## License

MIT — see [LICENSE](LICENSE).
