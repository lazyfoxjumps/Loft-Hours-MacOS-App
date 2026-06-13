import SwiftUI
import AppKit

/// An invisible, caret-free emoji input meant to sit on top of a SwiftUI circle
/// (the "+"/emoji glyph is drawn by SwiftUI underneath). It draws nothing and is
/// NOT a text field, so there is no field editor and therefore never an I-beam:
/// it's a plain NSView that becomes the first responder, shows a pointing-hand
/// cursor, opens the macOS emoji palette on every click, and receives the chosen
/// emoji through NSTextInputClient. Whatever the palette inserts is filtered down
/// to a single emoji before reaching the binding.
struct EmojiField: NSViewRepresentable {
    @Binding var emoji: String

    func makeCoordinator() -> Coordinator { Coordinator(emoji: $emoji) }

    func makeNSView(context: Context) -> EmojiInputView {
        let view = EmojiInputView()
        let coord = context.coordinator
        view.onPick = { inserted in
            if let kept = EmojiField.lastEmoji(in: inserted) {
                coord.emoji.wrappedValue = kept
            }
        }
        return view
    }

    func updateNSView(_ view: EmojiInputView, context: Context) {
        context.coordinator.emoji = $emoji
    }

    final class Coordinator {
        var emoji: Binding<String>
        init(emoji: Binding<String>) { self.emoji = emoji }
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

/// A transparent NSView that acts as an emoji-only input. It is the first
/// responder target for the system character palette and reports the inserted
/// text through `onPick`. Because it isn't an NSTextField there is no field
/// editor: the hover cursor stays a pointing hand and no caret ever appears.
final class EmojiInputView: NSView, @preconcurrency NSTextInputClient {
    var onPick: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Take focus if needed, then (re)open the palette on EVERY click so
        // changing your mind never takes several tries.
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        NSApp.orderFrontCharacterPalette(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if !text.isEmpty { onPick?(text) }
    }

    override func doCommand(by selector: Selector) {}
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Anchor the palette near the control.
        guard let window = window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}
