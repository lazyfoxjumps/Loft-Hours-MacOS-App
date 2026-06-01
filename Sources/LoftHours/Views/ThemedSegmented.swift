import SwiftUI

/// A segmented selector themed by the palette, replacing `Picker(.segmented)`.
/// The system segmented control renders with its own appearance (selection in
/// the system accent, default-color labels), which both clashes with our theme
/// and turns invisible on dark custom backgrounds. This draws its own segments
/// so selection uses the theme accent and labels always contrast the background.
struct ThemedSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    let palette: Palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { opt in
                segment(opt.value, opt.label)
            }
        }
    }

    private func segment(_ value: Value, _ label: String) -> some View {
        let isSelected = value == selection
        return Button {
            selection = value
        } label: {
            Text(label)
                .font(AppFont.nunito(12, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.background : palette.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? palette.accent : palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.surfaceBorder, lineWidth: isSelected ? 0 : 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
