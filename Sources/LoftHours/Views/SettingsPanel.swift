import SwiftUI

/// The unified settings sheet behind the gear button. Tabs: Theme (existing
/// palette picker) and Environment (Phase 3 toggles: Focus mode + app
/// management). Each Phase 3 integration is independently toggleable so the
/// app stays useful with everything off.
struct SettingsPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .theme
    /// Shortcut names found in the user's library; nil = not yet checked or the
    /// Shortcuts CLI isn't reachable.
    @State private var installedShortcuts: Set<String>? = nil
    /// Installed apps on this Mac, scanned once when Settings opens, used to
    /// power the type-ahead dropdown in the Manage apps lists.
    @State private var appsIndex = InstalledAppsIndex(apps: [])

    /// Whether both configured Focus shortcuts exist. Nil when we can't tell.
    private var focusShortcutsReady: Bool? {
        guard let installed = installedShortcuts else { return nil }
        return installed.contains(config.focusShortcutOn)
            && installed.contains(config.focusShortcutOff)
    }

    private func refreshShortcutStatus() {
        installedShortcuts = FocusService.installedShortcutNames()
    }

    enum Tab: String, CaseIterable, Identifiable {
        case theme = "Theme"
        case environment = "Environment"
        var id: String { rawValue }
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(AppFont.title3)
                    .foregroundStyle(p.foreground)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(p.muted)
            }

            ThemedSegmented(
                options: Tab.allCases.map { ($0, $0.rawValue) },
                selection: $tab,
                palette: p
            )

            Group {
                switch tab {
                case .theme: themeContent(p)
                case .environment: environmentContent(p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 380, height: 540)
        .background(p.background)
    }

    // MARK: - Theme tab

    private func themeContent(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a vibe.")
                .font(AppFont.caption)
                .foregroundStyle(p.muted)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ThemePreset.all) { preset in
                        presetPill(preset, selected: preset.id == theme.selected.id, palette: p)
                    }
                }
            }
        }
    }

    private func presetPill(_ preset: ThemePreset, selected: Bool, palette p: Palette) -> some View {
        Button {
            theme.select(preset)
        } label: {
            HStack {
                Text(preset.name)
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(Array(preset.swatches.enumerated()), id: \.offset) { _, c in
                        Circle()
                            .fill(c)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(p.surfaceBorder, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(p.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? p.accent : p.surfaceBorder, lineWidth: selected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Environment tab

    private func environmentContent(_ p: Palette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                focusSection(p)
                Divider().background(p.surfaceBorder)
                appsSection(p)
                Text("Each step runs only if its toggle is on. Failures are silent so a missing shortcut or app never breaks the session.")
                    .font(AppFont.caption)
                    .foregroundStyle(p.muted)
            }
        }
        .onAppear {
            if appsIndex.isEmpty { appsIndex = InstalledAppsIndex.scan() }
        }
    }

    private func focusSection(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $config.focusModeEnabled) {
                Text("Set Focus / Do Not Disturb")
                    .font(AppFont.headline)
                    .foregroundStyle(p.foreground)
            }
            .toggleStyle(.switch)
            .tint(p.accent)

            Text("Turns on Do Not Disturb when a session starts and off when it ends. macOS only lets apps do this through the Shortcuts app, so install the ready-made shortcuts once with the button below; no manual setup needed.")
                .font(AppFont.caption)
                .foregroundStyle(p.muted)

            shortcutStatusRow(p)

            DisclosureGroup("Advanced: shortcut names") {
                VStack(alignment: .leading, spacing: 10) {
                    labeled("Shortcut to enable", p: p) {
                        TextField("Loft Hours Focus On", text: $config.focusShortcutOn)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!config.focusModeEnabled)
                    }
                    labeled("Shortcut to disable", p: p) {
                        TextField("Loft Hours Focus Off", text: $config.focusShortcutOff)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!config.focusModeEnabled)
                    }
                }
                .padding(.top, 6)
            }
            .font(AppFont.caption)
            .foregroundStyle(p.muted)
            .disabled(!config.focusModeEnabled)
        }
        .onAppear(perform: refreshShortcutStatus)
    }

    @ViewBuilder
    private func shortcutStatusRow(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            switch focusShortcutsReady {
            case .some(true):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(p.done)
                Text("Focus shortcuts installed").font(AppFont.caption).foregroundStyle(p.foreground)
            case .some(false):
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(p.warn)
                Text("Not installed yet").font(AppFont.caption).foregroundStyle(p.foreground)
            case .none:
                Image(systemName: "questionmark.circle").foregroundStyle(p.muted)
                Text("Tap install, then confirm in Shortcuts").font(AppFont.caption).foregroundStyle(p.muted)
            }
            Spacer()
            Button(focusShortcutsReady == true ? "Reinstall" : "Install shortcuts") {
                FocusService.installBundledShortcuts()
                // Re-check after the user has had a moment to confirm the import.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: refreshShortcutStatus)
            }
            .buttonStyle(.bordered)
            .tint(p.accent)
            .controlSize(.small)
            .disabled(!config.focusModeEnabled)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.surfaceBorder, lineWidth: 1))
        )
    }

    private func appsSection(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $config.appManagementEnabled) {
                Text("Manage apps")
                    .font(AppFont.headline)
                    .foregroundStyle(p.foreground)
            }
            .toggleStyle(.switch)
            .tint(p.accent)

            Text("On start, the always-close apps quit and the focus apps launch. On wrap-up, optionally reopen anything that was closed.")
                .font(AppFont.caption)
                .foregroundStyle(p.muted)

            appList(title: "Always close", apps: $config.alwaysClose, palette: p)
            appList(title: "Open for focus", apps: $config.openForFocus, palette: p)

            Toggle(isOn: $config.restoreAppsAfter) {
                Text("Reopen closed apps after wrap-up")
                    .font(AppFont.callout)
                    .foregroundStyle(p.foreground)
            }
            .toggleStyle(.switch)
            .tint(p.accent)
            .disabled(!config.appManagementEnabled)
        }
    }

    private func appList(title: String, apps: Binding<[String]>, palette p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.nunito(11, .medium))
                .foregroundStyle(p.foreground)

            ForEach(apps.wrappedValue.indices, id: \.self) { idx in
                AppNameField(
                    text: Binding(
                        get: { apps.wrappedValue[idx] },
                        set: { apps.wrappedValue[idx] = $0 }
                    ),
                    palette: p,
                    enabled: config.appManagementEnabled,
                    index: appsIndex,
                    onRemove: { apps.wrappedValue.remove(at: idx) }
                )
            }

            Button {
                apps.wrappedValue.append("")
            } label: {
                Label("Add app", systemImage: "plus")
                    .font(AppFont.caption)
                    .foregroundStyle(p.accent)
            }
            .buttonStyle(.plain)
            .disabled(!config.appManagementEnabled)
        }
    }

    private func labeled<Content: View>(_ title: String, p: Palette, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(p.muted)
            content()
        }
    }
}
