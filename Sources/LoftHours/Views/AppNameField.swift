import SwiftUI
import AppKit

/// A text field for an app name with a live type-ahead dropdown of installed
/// apps. The user types by hand; matching apps on this Mac appear below the
/// field and a tap fills it in. The dropdown is inserted inline (it pushes
/// later rows down) rather than floated, so it never gets clipped by the
/// enclosing ScrollView.
struct AppNameField: View {
    @Binding var text: String
    let palette: Palette
    let enabled: Bool
    /// All installed app names, supplied by the parent so the disk scan happens
    /// once per Settings open instead of once per field.
    let index: InstalledAppsIndex
    let onRemove: () -> Void

    @FocusState private var focused: Bool

    private var suggestions: [InstalledApp] {
        guard focused else { return [] }
        return index.matches(text)
    }

    /// The app's real Finder icon, sized for a list row.
    private func icon(for app: InstalledApp) -> Image {
        let nsImage = NSWorkspace.shared.icon(forFile: app.url.path)
        nsImage.size = NSSize(width: 16, height: 16)
        return Image(nsImage: nsImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                TextField("App name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .disabled(!enabled)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
            }

            if enabled, !suggestions.isEmpty {
                dropdown
            }
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, app in
                Button {
                    text = app.name
                    focused = false
                } label: {
                    HStack(spacing: 8) {
                        icon(for: app)
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(app.name)
                            .font(AppFont.callout)
                            .foregroundStyle(palette.foreground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < suggestions.count - 1 {
                    Divider().background(palette.surfaceBorder)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.surfaceBorder, lineWidth: 1))
        )
        .padding(.top, 4)
        .padding(.trailing, 24) // align under the field, clear of the remove button
    }
}
