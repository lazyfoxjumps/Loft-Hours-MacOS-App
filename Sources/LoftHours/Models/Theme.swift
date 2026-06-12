import SwiftUI

/// A resolved color palette for the timer and screens. Mirrors the CSS custom
/// properties in the original `timer-template.html`: the five themeable colors
/// plus foreground/muted/surface values derived from the background's luminance
/// (so light academia themes don't render dark text on dark chrome).
struct Palette: Equatable {
    let accent: Color
    let background: Color
    let warn: Color
    let breakColor: Color
    let done: Color

    /// The Review > Logs calendar's activity color (the contribution-style
    /// circle behind active day numbers). Distinct from the five role colors.
    let activity: Color

    let foreground: Color
    let muted: Color
    let surface: Color
    let surfaceBorder: Color
    let doneBackground: Color

    let isLight: Bool

    // Kept so the calendar can composite the activity color over the
    // background at a given opacity and pick a legible day-number color.
    private let activityHex: String
    private let backgroundHex: String

    init(accentHex: String, backgroundHex: String, warnHex: String, breakHex: String, doneHex: String, activityHex: String) {
        accent = Color(hex: accentHex)
        background = Color(hex: backgroundHex)
        warn = Color(hex: warnHex)
        breakColor = Color(hex: breakHex)
        done = Color(hex: doneHex)
        activity = Color(hex: activityHex)
        self.activityHex = activityHex
        self.backgroundHex = backgroundHex

        // Same threshold and derived values as the template's luminance script.
        let light = Color.relativeLuminance(backgroundHex) > 0.55
        isLight = light
        if light {
            foreground = Color(hex: "2a1f15")
            muted = Color(hex: "2a1f15").opacity(0.55)
            surface = Color(hex: "281e14").opacity(0.06)
            surfaceBorder = Color(hex: "281e14").opacity(0.14)
            doneBackground = Color(hex: "231a14")
        } else {
            foreground = Color(hex: "e2e8f0")
            muted = Color(hex: "94a3b8")
            surface = Color.white.opacity(0.06)
            surfaceBorder = Color.white.opacity(0.12)
            doneBackground = Color(hex: "0a0a0a")
        }
    }

    /// Legible day-number color for a calendar cell whose circle is the
    /// activity color at `opacity` over the theme background. The text inverts
    /// against the effective fill: as the composite darkens the number goes
    /// light, and vice versa (matches the template's luminance approach).
    func activityDayTextColor(opacity: Double) -> Color {
        let l = Color.compositedLuminance(activityHex, over: backgroundHex, alpha: opacity)
        return l > 0.55 ? Color(hex: "2a1f15") : Color(hex: "e2e8f0")
    }
}

/// A named theme the user can pick from the gear panel.
struct ThemePreset: Identifiable, Equatable {
    let id: String        // stable key for persistence
    let name: String
    let accent: String
    let background: String
    let warn: String
    let breakHex: String
    let done: String
    let activity: String   // Review > Logs calendar activity color

    var palette: Palette {
        Palette(accentHex: accent, backgroundHex: background, warnHex: warn, breakHex: breakHex, doneHex: done, activityHex: activity)
    }

    /// The five swatch colors, in panel order.
    var swatches: [Color] {
        [Color(hex: accent), Color(hex: background), Color(hex: warn), Color(hex: breakHex), Color(hex: done)]
    }
}

extension ThemePreset {
    /// The seven curated palettes (2026-06 redesign): four dark-mode and three
    /// light-mode themes. Each maps a moodboard palette onto the five roles;
    /// `Palette.init` derives light vs dark chrome from the background.
    static let all: [ThemePreset] = [
        ThemePreset(id: "dark-academia", name: "Dark Academia",
                    accent: "A38860", background: "031100", warn: "390517", breakHex: "18302B", done: "EDEDED", activity: "6FA08C"),
        ThemePreset(id: "light-academia", name: "Light Academia",
                    accent: "8A4B32", background: "EADFC6", warn: "8B7A4D", breakHex: "3E4A2E", done: "4A3526", activity: "5C7A9E"),
        ThemePreset(id: "candlelit-nocturne", name: "Candlelit Nocturne",
                    accent: "C9A86A", background: "0C1424", warn: "3E5C8A", breakHex: "C7BCA8", done: "E8E2D4", activity: "A86A7B"),
        ThemePreset(id: "monochrome-magic", name: "Monochrome Magic",
                    accent: "B8AA9A", background: "1C1C1B", warn: "6A5D50", breakHex: "979086", done: "C8C0B0", activity: "7E9479"),
        ThemePreset(id: "modern-minimalist", name: "Modern Minimalist",
                    accent: "5B4738", background: "ECE6D6", warn: "B59C7D", breakHex: "9A9398", done: "C2C1A8", activity: "6B7FA3"),
        ThemePreset(id: "forest-cottagecore", name: "Forest Cottagecore",
                    accent: "6E8C50", background: "2C2010", warn: "C9B594", breakHex: "354B26", done: "E6DAC6", activity: "B07A8C"),
        ThemePreset(id: "linen-latte", name: "Linen & Latte",
                    accent: "87674C", background: "F2E2CF", warn: "B58F62", breakHex: "C6A98A", done: "3E322A", activity: "7C9070"),
    ]

    /// New users land on Light Academia; existing users keep whatever they saved.
    static let `default` = all.first { $0.id == "light-academia" } ?? all[0]

    static func with(id: String) -> ThemePreset {
        all.first { $0.id == id } ?? .default
    }
}

extension Color {
    /// Hex like "a78bfa" or "#a78bfa" (also accepts 3-digit shorthand).
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        let r = Double((n >> 16) & 0xff) / 255
        let g = Double((n >> 8) & 0xff) / 255
        let b = Double(n & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// The 0...255 R/G/B channels of a hex color (3- or 6-digit).
    static func channels255(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        return (Double((n >> 16) & 0xff), Double((n >> 8) & 0xff), Double(n & 0xff))
    }

    /// WCAG relative luminance from 0...255 channels.
    private static func luminance(r: Double, g: Double, b: Double) -> Double {
        let channels = [r, g, b].map { c -> Double in
            let v = c / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// WCAG relative luminance of a hex color, matching the template's script.
    static func relativeLuminance(_ hex: String) -> Double {
        let c = channels255(hex)
        return luminance(r: c.r, g: c.g, b: c.b)
    }

    /// Relative luminance of `fgHex` composited over `bgHex` at `alpha`, used to
    /// pick a legible day-number color over a translucent activity circle.
    static func compositedLuminance(_ fgHex: String, over bgHex: String, alpha: Double) -> Double {
        let f = channels255(fgHex)
        let b = channels255(bgHex)
        return luminance(
            r: f.r * alpha + b.r * (1 - alpha),
            g: f.g * alpha + b.g * (1 - alpha),
            b: f.b * alpha + b.b * (1 - alpha)
        )
    }
}
