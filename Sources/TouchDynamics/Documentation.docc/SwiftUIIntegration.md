# SwiftUI Integration

`touchDynamics(_:)` works on any view, inside any container.

## Items or containers

Apply the modifier to each item for independent feedback:

```swift
ScrollView {
    LazyVStack {
        ForEach(comments) { comment in
            CommentRow(comment: comment)
                .touchDynamics()
        }
    }
}
```

Or to the whole container for one shared surface:

```swift
ScrollView {
    LazyVStack { … }
}
.touchDynamics(.material)
```

When both a container and an item carry the modifier, the innermost surface
under the finger wins.

## Clipping

The effect surface is rectangular by default. Pass the same shape you use for
the content:

```swift
Card()
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .touchDynamics(.elastic, clipShape: RoundedRectangle(cornerRadius: 16))
```

## Placement and compositing

The surface is an overlay by default, composited with `multiply` in light
appearance and `screen` in dark appearance (``EffectCompositing/adaptive``),
so dark text stays dark and light text stays light. Set
``IlluminationConfiguration/placement`` to ``EffectPlacement/beneathContent``
to use `.background` instead; apply the modifier *before* any opaque
background in that case.

## How it works

- The modifier adds a `UIViewRepresentable` overlay that never hit-tests
  (`allowsHitTesting(false)`, `isUserInteractionEnabled = false`), so SwiftUI
  gestures and buttons are unaffected.
- The representable's view registers with a window-level observer that
  receives touches without claiming them; see <doc:GestureArbitration>.
- Deformation is a `GeometryEffect` marked `ignoredByLayout()`, so
  `GeometryReader`s and layout see the resting geometry.
- Illumination and ripple are drawn by Core Animation (or Metal) into the
  overlay; deformation is animated by SwiftUI with `interpolatingSpring`
  using the same `(mass, stiffness, damping)` as the UIKit path.

## Differences from UIKit

SwiftUI's `ScrollView` and `List` are backed by `UIScrollView` /
`UICollectionView`, so scroll takeover is detected the same way. Should a
future SwiftUI release change that, the drag heuristics in
``GestureConfiguration`` still dissipate the effect when the finger travels.
