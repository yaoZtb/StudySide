import AppKit
import SwiftUI
import WebKit

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

@main @MainActor struct AnswerScrollingTests {
    static func main() async throws {
        _ = NSApplication.shared
        let scroller = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        scroller.hasVerticalScroller = true
        let document = FlippedDocument(frame: CGRect(x: 0, y: 0, width: 380, height: 4000))
        scroller.documentView = document
        let source = (1...60).map { "Paragraph \($0): Read the course material, select a passage, and keep scrolling through this long answer." }.joined(separator: "\n\n")
        let representable = AnswerDocumentView(source: source, theme: .graphite, height: .constant(4000))
        let coordinator = representable.makeCoordinator()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(coordinator, name: "answerScroll")
        configuration.userContentController.add(coordinator, name: "answerHeight")
        let web = WKWebView(frame: document.bounds, configuration: configuration)
        web.navigationDelegate = coordinator
        document.addSubview(web)
        let window = NSWindow(contentRect: scroller.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroller
        let directory = AnswerDocumentView.resourceDirectory!
        web.loadFileURL(directory.appendingPathComponent("answer.html"), allowingReadAccessTo: directory)
        var ready = false
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("document.getElementById('answer').textContent.includes('Paragraph 60:')")) as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(ready, "Long answer did not load")
        let actualHeight = try await web.evaluateJavaScript("document.getElementById('answer').getBoundingClientRect().height") as! Double
        document.setFrameSize(CGSize(width: 380, height: max(1000, actualHeight)))
        web.setFrameSize(document.frame.size)
        scroller.contentView.scroll(to: .zero)
        let selection = """
        const range = document.createRange();
        range.setStart(document.querySelectorAll('p')[0].firstChild, 13);
        range.setEnd(document.querySelectorAll('p')[1].firstChild, 35);
        const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
        window.selectedAnswerText();
        """
        let copiedBefore = try await web.evaluateJavaScript(selection) as! String
        _ = try await web.evaluateJavaScript("document.body.dispatchEvent(new WheelEvent('wheel', {deltaY:220, bubbles:true, cancelable:true}))")
        try await Task.sleep(for: .milliseconds(100))
        let afterDown = scroller.contentView.bounds.minY
        precondition(afterDown > 100, "Vertical wheel was trapped in WebKit")
        let copiedAfter = try await web.evaluateJavaScript("window.selectedAnswerText()") as! String
        precondition(copiedBefore == copiedAfter, "Scrolling must not clear the cross-paragraph selection")
        _ = try await web.evaluateJavaScript("document.body.dispatchEvent(new WheelEvent('wheel', {deltaY:-100, bubbles:true, cancelable:true}))")
        try await Task.sleep(for: .milliseconds(100))
        precondition(scroller.contentView.bounds.minY < afterDown, "Upward scrolling failed")
        let beforeHorizontal = scroller.contentView.bounds.minY
        let horizontalDefault = try await web.evaluateJavaScript("document.body.dispatchEvent(new WheelEvent('wheel', {deltaX:180, deltaY:1, bubbles:true, cancelable:true}))") as! Bool
        try await Task.sleep(for: .milliseconds(50))
        precondition(horizontalDefault && scroller.contentView.bounds.minY == beforeHorizontal, "Horizontal formula scrolling must remain in WebKit")
        _ = try await web.evaluateJavaScript("document.body.dispatchEvent(new KeyboardEvent('keydown', {key:'PageDown', bubbles:true, cancelable:true}))")
        try await Task.sleep(for: .milliseconds(100))
        precondition(scroller.contentView.bounds.minY > beforeHorizontal, "Page Down did not scroll the chat")
        _ = try await web.evaluateJavaScript("document.body.dispatchEvent(new KeyboardEvent('keydown', {key:'End', bubbles:true, cancelable:true}))")
        try await Task.sleep(for: .milliseconds(100))
        let bottom = max(0, document.bounds.height - scroller.contentView.bounds.height)
        precondition(abs(scroller.contentView.bounds.minY - bottom) < 2, "End did not reach the last paragraph")
        _ = try await web.evaluateJavaScript("document.body.dispatchEvent(new KeyboardEvent('keydown', {key:'Home', bubbles:true, cancelable:true}))")
        try await Task.sleep(for: .milliseconds(100))
        precondition(scroller.contentView.bounds.minY < 1, "Home did not reach the first paragraph")
        AnswerScrolling.scroll(from: web, action: "wheel", delta: .nan)
        precondition(scroller.contentView.bounds.minY.isFinite, "Invalid scroll values must be ignored")
        print("PASS: long-answer wheel up/down, cross-paragraph selection during scrolling, horizontal gestures, Page Down, Home and End through the real WebKit-to-native bridge")
        configuration.userContentController.removeScriptMessageHandler(forName: "answerScroll")
        configuration.userContentController.removeScriptMessageHandler(forName: "answerHeight")
        web.navigationDelegate = nil
        window.contentView = nil
    }
}
