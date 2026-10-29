# ``TouchDynamics``

Physically responsive touch feedback for any UIKit or SwiftUI view: illumination
under the finger, a release ripple, and a damped elastic deformation — without
replacing a single gesture in your app.

## Overview

TouchDynamics observes touches; it never claims them. A single
window-level gesture recognizer that cannot prevent (or be prevented by) other
recognizers feeds a deterministic state machine, ``TouchInteractionEngine``,
which emits ``EngineCommand``s to a renderer. Scrolling, swiping, navigation
gestures, buttons and cell selection keep working exactly as before.

```swift
import TouchDynamics

CommentRow(comment: comment)
    .touchDynamics()
```

```swift
let attachment = TouchDynamics.attach(to: commentView, configuration: .default)
```

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:SwiftUIIntegration>
- <doc:UIKitIntegration>

### Configuration

- <doc:Configuring>
- ``TouchDynamicsConfiguration``
- ``IlluminationConfiguration``
- ``RippleConfiguration``
- ``ElasticityConfiguration``
- ``GestureConfiguration``
- ``RenderingConfiguration``
- ``AccessibilityConfiguration``
- ``EffectColor``

### Behavior

- <doc:GestureArbitration>
- <doc:Rendering>
- <doc:Accessibility>

### Engine

- ``TouchInteractionEngine``
- ``TouchSession``
- ``TouchPhase``
- ``TouchEngineState``
- ``TouchEvent``
- ``EngineCommand``
- ``TouchIdentifier``
- ``TouchDynamicsClock``
- ``MonotonicClock``

### Physics

- ``SpringSolver``
- ``IlluminationField``
- ``RippleWave``
- ``DeformationField``
- ``DeformationState``
- ``DeformationAnimation``

### Resolution

- ``ResolvedEffectAppearance``
- ``AccessibilityStatus``
- ``EffectAppearanceStyle``

### UIKit

- ``TouchDynamicsAttachment``
