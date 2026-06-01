import SwiftUI

/// Holds the selected theme and persists the choice. Phase 1 stores the
/// selection in UserDefaults; it moves into the app config (parity with the
/// skill's `config.json` theme) in a later phase.
@MainActor
final class ThemeStore: ObservableObject {
    @Published var selected: ThemePreset {
        didSet { UserDefaults.standard.set(selected.id, forKey: Self.key) }
    }

    var palette: Palette { selected.palette }

    private static let key = "lofthours.theme.id"

    init() {
        let savedID = UserDefaults.standard.string(forKey: Self.key) ?? ThemePreset.default.id
        selected = ThemePreset.with(id: savedID)
    }

    func select(_ preset: ThemePreset) {
        selected = preset
    }
}
