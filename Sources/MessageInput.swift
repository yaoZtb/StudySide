import AppKit
import SwiftUI

struct MessageInput: NSViewRepresentable {
    @Environment(\.studyTheme) private var theme
    @Binding var text: String
    let focusRequest: Int
    let send: () -> Void

    private static let font = NSFont.systemFont(ofSize: 13)
    private static let lineHeight: CGFloat = 17

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let editor = scroll.documentView as! NSTextView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.font = Self.font
        editor.textColor = NSColor(theme.ink)
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("What would you like to understand?")
        editor.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.input = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.textColor = NSColor(theme.ink)
        editor.insertionPointColor = NSColor(theme.accent)
        editor.font = NSFont.systemFont(ofSize: 13)
        scroll.appearance = NSAppearance(named: theme.colorScheme == .dark ? .darkAqua : .aqua)
        if editor.string != text && !editor.hasMarkedText() {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if coordinator.lastFocusRequest != focusRequest {
            coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor else { return }
                editor.window?.makeFirstResponder(editor)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let content = text.hasSuffix("\n") ? text + " " : text
        let height = (content as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.font]
        ).height
        return CGSize(width: width, height: max(2 * Self.lineHeight, min(6 * Self.lineHeight, ceil(height) + 3)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var input: MessageInput
        var lastFocusRequest: Int

        init(_ input: MessageInput) {
            self.input = input
            lastFocusRequest = input.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            input.text = editor.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  !textView.hasMarkedText(),
                  let event = NSApp.currentEvent,
                  event.type == .keyDown,
                  event.keyCode == 36 || event.keyCode == 76,
                  event.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty
            else { return false }
            if !event.isARepeat {
                input.text = textView.string
                input.send()
            }
            return true
        }
    }
}
