import AppKit

@main @MainActor struct WindowLevelTests {
    static func main() {
        _ = NSApplication.shared
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        let controller = WindowLevelView()
        first.contentView!.addSubview(controller)
        precondition(first.level == .normal, "Default window must allow ordinary stacking")
        controller.pinned = true
        precondition(first.level == .floating, "Manual pin must raise the window level")
        controller.pinned = false
        precondition(first.level == .normal, "Unpin must restore ordinary stacking")
        controller.removeFromSuperview()
        controller.pinned = true
        first.contentView!.addSubview(controller)
        precondition(first.level == .floating, "Pin set before attachment must be applied on attachment")
        let second = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        controller.removeFromSuperview()
        controller.pinned = false
        second.contentView!.addSubview(controller)
        precondition(second.level == .normal, "Reattached ordinary window must remain ordinary")
        print("PASS: normal by default; pin, unpin, delayed attachment and reattachment behave correctly")
    }
}
