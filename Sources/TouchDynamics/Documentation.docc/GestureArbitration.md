# Gesture Arbitration

TouchDynamics must never hijack the host app's gestures. Here is how it avoids
that while still feeling attached to the finger.

## Observation, not recognition

One ``TouchDynamics`` gesture recognizer is installed per `UIWindow`. It

- overrides `canPrevent(_:)` and `canBePrevented(by:)` to return `false`,
- sets `cancelsTouchesInView`, `delaysTouchesBegan` and `delaysTouchesEnded`
  to `false`,
- recognizes simultaneously with every other recognizer,
- never leaves the `.possible` state while touches are down and moves to
  `.failed` once the touch sequence ends, so UIKit resets it.

In `gestureRecognizer(_:shouldReceive:)` the recognizer decides per touch
whether any registered surface is under the finger. The touch's hit-test view
must be inside the surface's view, or the surface's view inside the hit-test
view (SwiftUI content, non-interactive UIKit views). The deepest matching
surface wins, then the smallest. Touches that match nothing are not delivered
to the recognizer at all.

Because the recognizer sits on the window, feedback starts on the same frame
the touch lands even inside scroll views with `delaysContentTouches`.

## Interpretation

| Gesture | Effect |
| --- | --- |
| Tap | Illuminate → ripple → spring release |
| Long press | Illumination and deformation deepen after ``GestureConfiguration/longPressDuration`` |
| Vertical scroll | Ancestor scroll view's pan begins → effect dissipates, no ripple |
| Horizontal swipe | Preserved; the effect tracks within the slop then dissipates with the scroll |
| Drag | Beyond ``GestureConfiguration/tapSlop``: ``DragBehavior/follow`` (default) or ``DragBehavior/dissipate`` |
| Drag out | Beyond bounds + ``GestureConfiguration/exitMargin``: dims, release dissipates |
| Cancellation | ``CancellationBehavior/dissipate`` or ``CancellationBehavior/suppress`` |
| Multi-touch | Independent sessions up to ``GestureConfiguration/maximumConcurrentTouches`` |
| Reused cell | Leaving the window resets everything instantly |

## Scroll detection

At touch-down the attachment adds a target-action to the
`panGestureRecognizer` of every ancestor `UIScrollView` (nested containers
included). When any pan enters `.began` the engine receives
``TouchInteractionEngine/scrollDidBegin(at:)``: active sessions dissipate and
new fingers during the scroll show nothing, matching native highlight behavior.
Targets are removed when the last finger lifts. As a fallback the attachment
also checks `isDragging` on each move.

## State machine

```
idle → pressing → tracking → releasing → settling → idle
          │          │
          ├──────────┴──→ scrolling  (ancestor scroll began)
          └──────────┴──→ cancelled  (system cancel, drag out, drag with .dissipate)
detached (terminal)
```

``TouchInteractionEngine`` has no timers; the attachment calls
``TouchInteractionEngine/tick(now:)`` for long-press promotion and as a safety
net if a renderer never reports completion.
