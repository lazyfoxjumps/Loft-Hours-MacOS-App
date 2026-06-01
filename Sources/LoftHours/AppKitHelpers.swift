import AppKit
import SwiftUI

/// Images bundled in `Contents/Resources/Images`, loaded by name at runtime.
enum AppImages {
    static func bundled(_ name: String, ext: String = "png") -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Images") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// The favicon used as the menu-bar icon, sized for the status bar. Rendered
    /// as a template (monochrome line-art) so it stays visible on both light and
    /// dark menu bars instead of disappearing on one of them.
    static let menuBar: NSImage? = {
        guard let img = bundled("MenuBarIcon") else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()

    /// URL of the notification thumbnail icon, for UNNotificationAttachment.
    static var notificationIconURL: URL? {
        Bundle.main.url(forResource: "NotificationIcon", withExtension: "png", subdirectory: "Images")
    }
}

/// Brings Loft Hours and its main window back to the front. Used after session
/// start (where launching focus apps or running the DND Shortcut can steal
/// focus and push our window behind) and when opening Review from the menu bar.
enum AppActivator {
    @MainActor
    static func bringToFront() {
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)
        for window in app.windows where window.styleMask.contains(.titled) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
