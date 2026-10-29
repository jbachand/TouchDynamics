# Accessibility

Feedback adapts to the user's settings at touch-down.

## Reduce Motion

With ``AccessibilityConfiguration/respectsReduceMotion`` (default on) and
Reduce Motion enabled:

- the illumination still appears under the finger and stays anchored,
- the release is a non-moving cross-fade with a brief flat flash,
- no deformation is applied.

Set ``AccessibilityConfiguration/reducedMotionBehavior`` to
``ReducedMotionBehavior/none`` for no feedback at all.

## Reduce Transparency

The Gaussian field is replaced by a flat highlight covering the surface at
``AccessibilityConfiguration/reducedTransparencyIntensity``, with no blend
mode, so the highlight is predictable and high-contrast.

## VoiceOver

Touches still produce feedback, but deformation is disabled so the focused
element's geometry stays stable
(``AccessibilityConfiguration/disablesDeformationForVoiceOver``). The effect
surface is never an accessibility element and never hit-tests, so the
accessibility tree of the host is unchanged.

## Testing

``ResolvedEffectAppearance`` is the single place where these rules live and is
constructed from an ``AccessibilityStatus`` you can inject in tests.
