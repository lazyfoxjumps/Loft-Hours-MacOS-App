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

    let foreground: Color
    let muted: Color
    let surface: Color
    let surfaceBorder: Color
    let doneBackground: Color

    let isLight: Bool

    init(accentHex: String, backgroundHex: String, warnHex: String, breakHex: String, doneHex: String) {
        accent = Color(hex: accentHex)
        background = Color(hex: backgroundHex)
        warn = Color(hex: warnHex)
        breakColor = Color(hex: breakHex)
        done = Color(hex: doneHex)

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

    var palette: Palette {
        Palette(accentHex: accent, backgroundHex: background, warnHex: warn, breakHex: breakHex, doneHex: done)
    }

    /// The five swatch colors, in panel order.
    var swatches: [Color] {
        [Color(hex: accent), Color(hex: background), Color(hex: warn), Color(hex: breakHex), Color(hex: done)]
    }
}

extension ThemePreset {
    /// Classic midnight (the original config default) plus the five academia
    /// presets from the timer template, in the same order.
    static let all: [ThemePreset] = [
        ThemePreset(id: "midnight", name: "Classic Midnight",
                    accent: "a78bfa", background: "0f172a", warn: "f59e0b", breakHex: "22c55e", done: "22c55e"),
        ThemePreset(id: "dark-academia", name: "Dark Academia",
                    accent: "8b2e3b", background: "1c1410", warn: "c9933b", breakHex: "6b7e5c", done: "a8895d"),
        ThemePreset(id: "light-academia", name: "Light Academia",
                    accent: "5c3a1e", background: "efe4ce", warn: "b07d2f", breakHex: "8e9b81", done: "a47358"),
        ThemePreset(id: "forest-cottagecore", name: "Forest Cottagecore",
                    accent: "6b8e5a", background: "1a201a", warn: "c98a3f", breakHex: "a8b89f", done: "a86b4f"),
        ThemePreset(id: "candlelit-nocturne", name: "Candlelit Nocturne",
                    accent: "d4a755", background: "0c1424", warn: "cc6633", breakHex: "6a89a8", done: "b8a888"),
        ThemePreset(id: "linen-latte", name: "Linen & Latte",
                    accent: "4a2e1f", background: "ede2cf", warn: "c47b3d", breakHex: "9aa490", done: "b08374"),
    ]

    static let `default` = all[0]

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

    /// WCAG relative luminance of a hex color, matching the template's script.
    static func relativeLuminance(_ hex: String) -> Double {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        let channels = [Double((n >> 16) & 0xff), Double((n >> 8) & 0xff), Double(n & 0xff)].map { c -> Double in
            let v = c / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
