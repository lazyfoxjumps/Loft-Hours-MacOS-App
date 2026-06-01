import SwiftUI

/// Nunito-based typography for the app's text.
///
/// Nunito (OFL, bundled in `Resources/Fonts`) is the main typeface for all
/// copy: titles, field labels, body text. Two things deliberately stay on the
/// system font (San Francisco): the timer's monospaced countdown digits, where
/// SF's tabular figures read cleaner, and SF Symbol glyphs, which only render
/// in the system font. If Nunito ever fails to register, `Font.custom` falls
/// back to the system font automatically, so text never disappears.
///
/// Sizes mirror the macOS semantic styles they replace so existing layouts
/// stay put; the helper just swaps the family.
enum AppFont {
    /// A Nunito face at the given size/weight. Nunito ships as a variable font,
    /// so `.weight(_:)` resolves to the matching point on its weight axis.
    static func nunito(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Nunito", size: size).weight(weight)
    }

    /// Gaegu (OFL, Bold weight bundled) — the handwritten display face used for
    /// anything that IS the "Loft Hours" logo/wordmark. Sized up from body copy
    /// since handwriting faces read smaller at a given point size.
    static func gaegu(_ size: CGFloat) -> Font {
        .custom("Gaegu", size: size).weight(.bold)
    }

    /// The big "Loft Hours" wordmark on the intake screen.
    static let wordmark = gaegu(40)

    /// Primary per-screen heading (e.g. "Nice work!", "Block 2 done.",
    /// "Session logged") — the Gaegu logo face, sized between the wordmark and
    /// body copy.
    static let heading = gaegu(32)

    /// The small "Loft Hours" footer mark shown on every page.
    static let footerMark = gaegu(15)

    static let largeTitle = nunito(26, .semibold)
    static let title      = nunito(22, .semibold)
    static let title2     = nunito(17, .semibold)
    static let title3     = nunito(15, .semibold)
    static let headline   = nunito(13, .semibold)
    static let body       = nunito(13)
    static let callout    = nunito(12)
    static let subheadline = nunito(11)
    static let caption    = nunito(10)
}
