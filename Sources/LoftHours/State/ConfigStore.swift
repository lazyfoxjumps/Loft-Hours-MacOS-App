import Foundation
import SwiftUI

/// Persisted user settings for Phase 3 environment integrations.
/// Both integrations default off so the app stays useful without them.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var focusModeEnabled: Bool {
        didSet { defaults.set(focusModeEnabled, forKey: Keys.focusModeEnabled) }
    }
    @Published var focusShortcutOn: String {
        didSet { defaults.set(focusShortcutOn, forKey: Keys.focusShortcutOn) }
    }
    @Published var focusShortcutOff: String {
        didSet { defaults.set(focusShortcutOff, forKey: Keys.focusShortcutOff) }
    }

    @Published var appManagementEnabled: Bool {
        didSet { defaults.set(appManagementEnabled, forKey: Keys.appManagementEnabled) }
    }
    @Published var alwaysClose: [String] {
        didSet { defaults.set(alwaysClose, forKey: Keys.alwaysClose) }
    }
    @Published var openForFocus: [String] {
        didSet { defaults.set(openForFocus, forKey: Keys.openForFocus) }
    }
    @Published var restoreAppsAfter: Bool {
        didSet { defaults.set(restoreAppsAfter, forKey: Keys.restoreAppsAfter) }
    }

    // Google Calendar sync. The OAuth tokens live in the Keychain (see
    // GoogleAuth); these are just the user's preference + a display mirror.
    @Published var calendarSyncEnabled: Bool {
        didSet { defaults.set(calendarSyncEnabled, forKey: Keys.calendarSyncEnabled) }
    }
    @Published var calendarId: String {
        didSet { defaults.set(calendarId, forKey: Keys.calendarId) }
    }
    @Published var calendarConnectedEmail: String? {
        didSet { defaults.set(calendarConnectedEmail, forKey: Keys.calendarConnectedEmail) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let focusModeEnabled = "lofthours.focus.enabled"
        static let focusShortcutOn = "lofthours.focus.shortcut.on"
        static let focusShortcutOff = "lofthours.focus.shortcut.off"
        static let appManagementEnabled = "lofthours.apps.enabled"
        static let alwaysClose = "lofthours.apps.alwaysClose"
        static let openForFocus = "lofthours.apps.openForFocus"
        static let restoreAppsAfter = "lofthours.apps.restoreAfter"
        static let calendarSyncEnabled = "lofthours.calendar.enabled"
        static let calendarId = "lofthours.calendar.id"
        static let calendarConnectedEmail = "lofthours.calendar.email"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.focusModeEnabled = defaults.bool(forKey: Keys.focusModeEnabled)
        self.focusShortcutOn = defaults.string(forKey: Keys.focusShortcutOn) ?? "Loft Hours Focus On"
        self.focusShortcutOff = defaults.string(forKey: Keys.focusShortcutOff) ?? "Loft Hours Focus Off"
        self.appManagementEnabled = defaults.bool(forKey: Keys.appManagementEnabled)
        self.alwaysClose = defaults.stringArray(forKey: Keys.alwaysClose) ?? []
        self.openForFocus = defaults.stringArray(forKey: Keys.openForFocus) ?? []
        if defaults.object(forKey: Keys.restoreAppsAfter) == nil {
            self.restoreAppsAfter = true
        } else {
            self.restoreAppsAfter = defaults.bool(forKey: Keys.restoreAppsAfter)
        }
        self.calendarSyncEnabled = defaults.bool(forKey: Keys.calendarSyncEnabled)
        self.calendarId = defaults.string(forKey: Keys.calendarId) ?? "primary"
        self.calendarConnectedEmail = defaults.string(forKey: Keys.calendarConnectedEmail)
    }
}
