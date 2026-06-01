import Foundation

/// One installed app: the name we store/match on plus the bundle URL so the UI
/// can show its real icon. `name` is the bundle filename without `.app`, which
/// is exactly what `AppManager` matches against and what `open -a "<name>"`
/// accepts, so a picked name always resolves later.
struct InstalledApp: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: String { name }
}

/// Scans the standard macOS application directories for installed `.app`
/// bundles so the settings UI can offer a type-ahead list with icons.
struct InstalledAppsIndex {

    let apps: [InstalledApp]

    var isEmpty: Bool { apps.isEmpty }

    /// The roots we look in. Each is scanned one level deep, and one level into
    /// any non-`.app` subfolder (so `/Applications/Utilities/*.app` and vendor
    /// folders like `/Applications/Adobe.../*.app` are found) without descending
    /// into the bundles themselves.
    private static let roots: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications",
            "/System/Applications",
            "\(home)/Applications",
        ]
    }()

    /// Build the index by scanning disk. Cheap enough (a few hundred shallow
    /// `contentsOfDirectory` reads) to run on demand when Settings opens.
    static func scan() -> InstalledAppsIndex {
        let fm = FileManager.default
        // First URL wins per name, so /Applications shadows duplicates elsewhere.
        var byName: [String: URL] = [:]

        func add(_ url: URL) {
            let name = url.deletingPathExtension().lastPathComponent
            if byName[name] == nil { byName[name] = url }
        }

        for root in roots {
            guard let top = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in top {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // One level deeper for nested apps; never descend into a bundle.
                    if let nested = try? fm.contentsOfDirectory(
                        at: item,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) {
                        for sub in nested where sub.pathExtension == "app" {
                            add(sub)
                        }
                    }
                }
            }
        }

        let apps = byName
            .map { InstalledApp(name: $0.key, url: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return InstalledAppsIndex(apps: apps)
    }

    /// Apps whose name contains `query`, prefix matches first, capped to `limit`.
    /// Returns empty when the query is blank or already exactly names an app
    /// (so the dropdown disappears once a selection is locked in).
    func matches(_ query: String, limit: Int = 6) -> [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        if apps.contains(where: { $0.name.lowercased() == q }) { return [] }
        return apps
            .filter { $0.name.lowercased().contains(q) }
            .sorted { lhs, rhs in
                let lp = lhs.name.lowercased().hasPrefix(q)
                let rp = rhs.name.lowercased().hasPrefix(q)
                if lp != rp { return lp }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }
}
