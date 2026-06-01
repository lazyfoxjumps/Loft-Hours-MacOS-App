import Foundation
import AppKit

/// Open and close apps for the focus ritual via NSWorkspace.
///
/// Names match what the user types in the settings list. We resolve each name
/// against running apps (`localizedName` / `bundleURL.lastPathComponent`) and
/// fall back to `NSWorkspace.urlForApplication(withName:)` for launching. Quit
/// uses `NSRunningApplication.terminate()` (graceful). If the entitlement for
/// Apple Events isn't granted, an osascript fallback is tried; if that also
/// fails, the step is dropped silently.
struct AppManager {

    /// Quit each named app. Returns the names that were actually closed so the
    /// caller can offer to reopen them at wrap-up.
    @discardableResult
    func close(_ names: [String]) -> [String] {
        var closed: [String] = []
        let running = NSWorkspace.shared.runningApplications
        for name in names.map(normalize).filter({ !$0.isEmpty }) {
            let hits = running.filter { matches(app: $0, name: name) }
            guard !hits.isEmpty else { continue }
            var didClose = false
            for app in hits {
                if app.terminate() {
                    didClose = true
                } else {
                    didClose = quitViaAppleScript(name: name) || didClose
                }
            }
            if didClose { closed.append(name) }
        }
        return closed
    }

    func open(_ names: [String]) {
        for name in names.map(normalize).filter({ !$0.isEmpty }) {
            launch(name: name)
        }
    }

    // MARK: - Helpers

    private func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(app: NSRunningApplication, name: String) -> Bool {
        let target = name.lowercased()
        if let localized = app.localizedName?.lowercased(), localized == target { return true }
        if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased(),
           bundleName == target { return true }
        return false
    }

    private func launch(name: String) {
        // `open -a "<Name>"` is the simplest path that accepts a user-typed app
        // name. NSWorkspace's URL lookup only takes a bundle identifier; asking
        // the user for one would be hostile to the typical "Notes" / "Safari"
        // input we expect here. `-g` launches in the background so the focus app
        // never steals foreground from the running timer window.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-a", name]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try? process.run()
    }

    @discardableResult
    private func quitViaAppleScript(name: String) -> Bool {
        let script = "tell application \"\(name)\" to quit"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
