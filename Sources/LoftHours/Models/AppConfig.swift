import Foundation

/// App-level settings. Phase 1 only needs the log directory; this is the
/// seam where the `config.json` schema (themes, reminders, app lists) lands
/// in later phases. Replaces the skill's `config.json`.
struct AppConfig {
    /// Where session logs are written. Defaults to the same folder the skill
    /// uses, so existing logs and app logs live side by side.
    var logDirectory: URL

    static let `default` = AppConfig(
        logDirectory: URL(fileURLWithPath: NSString(string: "~/Documents/study-log").expandingTildeInPath, isDirectory: true)
    )
}
