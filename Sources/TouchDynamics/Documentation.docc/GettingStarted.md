# Getting Started

Add the package, apply one modifier or one call, and tune from a preset.

## Install

In Xcode choose **File ▸ Add Package Dependencies…** and enter the repository
URL, or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jbachand/TouchDynamics.git", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: ["TouchDynamics"]),
]
```

TouchDynamics requires iOS 16 and Swift 5.9, has no third-party dependencies,
and is Swift 6 strict-concurrency clean.

## SwiftUI

```swift
import TouchDynamics

struct CommentView: View {
    var body: some View {
        CommentContent()
            .touchDynamics()
    }
}
```

## UIKit

```swift
import TouchDynamics

let attachment = TouchDynamics.attach(to: commentView, configuration: .default)
```

## Pick a preset

| Preset | Behavior |
| --- | --- |
| `.whisper` | Barely there: noticeable only if you look for it |
| `.faint` | Noticeably quieter than subtle |
| `.subtle` (default) | Soft illumination, minimal deformation |
| `.fluid` | Bright ripple, gentle directional elasticity |
| `.elastic` | Stronger spring and touch deformation |
| `.material` | Soft, diffused, surface-oriented feedback |
| `.rippleOnly` | Illumination and wave without deformation |
| `.custom(…)` | Fully configurable |

```swift
var config = TouchDynamicsConfiguration.fluid
config.illumination.radius = 90
config.ripple.duration = 0.3
config.elasticity.damping = 0.8

CommentContent().touchDynamics(config)
```
