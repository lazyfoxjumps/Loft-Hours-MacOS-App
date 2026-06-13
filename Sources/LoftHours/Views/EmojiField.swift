import SwiftUI
import AppKit

/// A borderless, caret-free emoji input. It draws nothing on its own (the
/// SwiftUI wrapper supplies the circle + "+" affordance); it exists only to be
/// the first responder so a click pops the macOS emoji/character palette, and
/// to filter whatever gets inserted down to a single emoji. No placeholder, no
/// blinking insertion point, no bezel.
struct EmojiField: NSViewRepresentable {
    @Binding var emoji: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> EmojiNSTextField {
        let field = EmojiNSTextField()
        field.delegate = context.coordinator
        field.alignment = .center
        field.font = .systemFont(ofSize: 15)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.stringValue = emoji
        field.refusesFirstResponder = false
        return field
    }

    func updateNSView(_ field: EmojiNSTextField, context: Context) {
        if field.stringValue != emoji {
            field.stringValue = emoji
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: EmojiField

        init(_ parent: EmojiField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            // Keep only the last emoji grapheme; reject plain text/whitespace.
            let kept = EmojiField.lastEmoji(in: field.stringValue) ?? ""
            if field.stringValue != kept {
                field.stringValue = kept
            }
            if parent.emoji != kept {
                parent.emoji = kept
            }
        }
    }

    /// The last grapheme cluster in `text` that reads as an emoji, or nil.
    static func lastEmoji(in text: String) -> String? {
        for cluster in text.reversed().map(String.init) where isEmoji(cluster) {
            return cluster
        }
        return nil
    }

    private static func isEmoji(_ cluster: String) -> Bool {
        cluster.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji && (scalar.value > 0x238C || scalar.properties.isEmojiPresentation)
        }
    }
}

/// An NSTextField that behaves like a button: every click (re)opens the system
/// character palette, the hover cursor is a pointing hand rather than an I-beam,
/// and the blinking caret is suppressed while it holds focus. The caret is
/// cleared on the shared field editor only while this field is edited, then
/// restored on end-editing so other text fields keep their cursor.
final class EmojiNSTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            (currentEditor() as? NSTextView)?.insertionPointColor = .clear
        }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        // Restore the shared field editor's caret for the next text field.
        (notification.object as? NSTextView)?.insertionPointColor = .textColor
        super.textDidEndEditing(notification)
    }

    override func mouseDown(with event: NSEvent) {
        // Take focus if we don't have it, then open the palette on EVERY click
        // so changing your mind doesn't take several tries. Deliberately skip
        // super so the click doesn't place a text caret.
        if currentEditor() == nil {
            window?.makeFirstResponder(self)
        }
        NSApp.orderFrontCharacterPalette(self)
    }

    override func resetCursorRects() {
        // It's a picker button, not a text box: show the pointing hand on hover.
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
