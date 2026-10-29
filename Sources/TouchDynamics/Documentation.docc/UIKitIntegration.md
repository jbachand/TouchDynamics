# UIKit Integration

Attach to any `UIView`, `UIControl` or cell. No subclassing.

## Attach and detach

```swift
let attachment = TouchDynamics.attach(to: view, configuration: .fluid)
// later
attachment.detach()           // or TouchDynamics.detach(from: view)
```

`attach(to:)` is idempotent: calling it again updates the configuration and
returns the same ``TouchDynamicsAttachment``. Look it up any time with
`view.touchDynamicsAttachment`.

## Cells

```swift
func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Comment", for: indexPath)
    TouchDynamics.attach(to: cell)
    …
    return cell
}
```

The effect is hosted in `contentView`, deformation is applied to `contentView`
(so table-view animations that manage the cell's own transform are
unaffected), and everything resets automatically when the cell leaves the
window. Call ``TouchDynamicsAttachment/reset()`` from `prepareForReuse` if you
want to be explicit.

## Controls

For `UIControl`s the surface is placed above the content so filled buttons
still show the effect, and the control's own highlight, actions and
accessibility are untouched. Nothing is added to the control's gesture
recognizers.

## Placement and clipping

- ``EffectPlacement/automatic``: beneath subviews for plain views, above
  content for controls. Override with ``IlluminationConfiguration/placement``.
- ``EffectClipShape/automatic``: mirrors the view's `cornerRadius`,
  `cornerCurve` and `maskedCorners`. Use ``RenderingConfiguration/clipShape``
  or ``TouchDynamicsAttachment/clipPathProvider`` for other shapes.

## Transforms

Deformation is applied through `transform`, composed on top of whatever
transform the view had when the press began. Layout (`center`, `bounds`,
Auto Layout) is never touched. If your code changes the view's transform during
a press, the attachment steps aside for that press rather than fighting; if
your views animate their own transform on highlight, use `.rippleOnly` or set
`elasticity.isEnabled = false`.

## Views that ignore touches

Views such as `UILabel` have `isUserInteractionEnabled == false`. TouchDynamics
does not change that: because touches are observed at the window and matched by
geometry and hit-view ancestry, a label still lights up without becoming
interactive.
