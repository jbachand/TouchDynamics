import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// The color used for illumination and ripple effects.
///
/// Colors are resolved at touch time against the host view's trait collection
/// and tint color, so appearance changes are picked up automatically.
public enum EffectColor: Equatable {
    /// White light in both appearances: whatever is under the finger gets
    /// lighter. On a pure white surface only the content (text, images)
    /// shows it; on any darker surface the surface itself brightens.
    ///
    /// This is the default. For a shade that darkens instead, use
    /// ``adaptiveInk``.
    case adaptive

    /// Black in light appearance, white in dark: a shade rather than a light.
    /// Reads as a soft press shadow on light surfaces.
    case adaptiveInk

    /// The host view's effective `tintColor` (UIKit) or accent color.
    case tint

    /// An explicit sRGB color. Alpha is multiplied by the effect intensity.
    case rgba(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)

    #if canImport(UIKit)
    /// An explicit `UIColor`. Dynamic colors are resolved for the view's traits.
    case uiColor(UIColor)
    #endif

    /// A fully opaque white.
    public static let white = EffectColor.rgba(red: 1, green: 1, blue: 1, alpha: 1)
    /// A fully opaque black.
    public static let black = EffectColor.rgba(red: 0, green: 0, blue: 0, alpha: 1)

    #if canImport(UIKit)
    /// Creates an effect color from a `UIColor`.
    public static func color(_ color: UIColor) -> EffectColor { .uiColor(color) }
    #endif

    #if canImport(SwiftUI) && canImport(UIKit)
    /// Creates an effect color from a SwiftUI `Color`.
    public static func color(_ color: Color) -> EffectColor { .uiColor(UIColor(color)) }
    #endif
}

// `UIColor` is immutable and documented as thread-safe; the enum is marked
// unchecked so the configuration structs that embed it stay `Sendable`.
extension EffectColor: @unchecked Sendable {}
