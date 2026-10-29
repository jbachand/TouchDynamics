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

Three more signals cover the gaps:

- **Surface movement.** The attachment records a window-space reference at
  touch-down (the scroll view's content view in SwiftUI, the view's `center`
  in UIKit) and treats movement beyond
  ``GestureConfiguration/scrollDetectionDistance`` as a scroll. This works for
  containers that are not `UIScrollView`-backed.
- **Catching a moving list.** A finger landing while an ancestor scroll view
  is dragging or decelerating shows nothing, like a native highlight.
- **Scroll end at touch-up.** A scroll cannot continue without a finger, so
  when the last finger lifts the attachment closes the scroll itself; it does
  not wait for the pan's own end, which can arrive after the touch-up. The
  engine applies the same rule when a new finger lands with no sessions left.

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
