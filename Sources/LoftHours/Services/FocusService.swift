import Foundation
import AppKit

/// Toggles macOS Focus / Do Not Disturb by running a user-configured Shortcut.
///
/// The sandbox can't toggle Focus directly, so we delegate to the Shortcuts
/// app. Two paths:
///   1. `shortcuts run "<name>"` via Process when available (ad-hoc builds).
///   2. `shortcuts://run-shortcut?name=<name>` x-callback-url (always works,
///      including a future signed/sandboxed Mac App Store build).
///
/// The x-callback-url path is the durable one; the Process path is a faster
/// no-bounce option when the CLI is reachable. Failures are silent: the spec
/// says environment steps never break the session.
struct FocusService {
    var shortcutOn: String
    var shortcutOff: String

    func enable() { run(shortcutOn) }
    func disable() { run(shortcutOff) }

    private func run(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if runViaCLI(trimmed) { return }
        runViaURL(trimmed)
    }

    @discardableResult
    private func runViaCLI(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: "/usr/bin/shortcuts")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
        let process = Process()
        process.executableURL = url
        process.arguments = ["run", name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runViaURL(_ name: String) {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return }
        // Run the shortcut without bringing the Shortcuts app to the foreground,
        // so it doesn't steal focus from the running timer window.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
    }
}

// MARK: - One-click install + detection

extension FocusService {
    /// The two ready-made Focus shortcuts bundled in the app (signed, importable
    /// with a single "Add Shortcut" tap). Filenames match the default shortcut
    /// names in `ConfigStore`.
    static let bundledNames = ["Loft Hours Focus On", "Loft Hours Focus Off"]

    /// URLs of the bundled `.shortcut` files, if present in the app bundle.
    static func bundledShortcutURLs() -> [URL] {
        bundledNames.compactMap {
            Bundle.main.url(forResource: $0, withExtension: "shortcut", subdirectory: "Shortcuts")
        }
    }

    /// Open the bundled shortcut files so Shortcuts shows its one-tap "Add
    /// Shortcut" sheet for each. The user confirms once; after that the session
    /// start/stop runs them automatically.
    static func installBundledShortcuts() {
        let urls = bundledShortcutURLs()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls.first!)
        // Stagger the second so both import sheets don't collide.
        if urls.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSWorkspace.shared.open(urls[1])
            }
        }
    }

    /// Names of shortcuts currently in the user's library, via the `shortcuts`
    /// CLI. Returns nil if the CLI isn't reachable (e.g. a future sandboxed
    /// build), so callers can fall back to "unknown" rather than "missing".
    static func installedShortcutNames() -> Set<String>? {
        let url = URL(fileURLWithPath: "/usr/bin/shortcuts")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            let names = text.split(separator: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return Set(names.filter { !$0.isEmpty })
        } catch {
            return nil
        }
    }
}
