import SwiftUI
import WebKit

extension AnswerFormatting {
    static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func inlineHTML(_ source: String) -> String {
        let attributed = inline(source)
        return attributed.runs.map { run in
            var html = escapeHTML(String(attributed[run.range].characters))
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { html = "<code>" + html + "</code>" }
                if intent.contains(.stronglyEmphasized) { html = "<strong>" + html + "</strong>" }
                if intent.contains(.emphasized) { html = "<em>" + html + "</em>" }
                if intent.contains(.strikethrough) { html = "<s>" + html + "</s>" }
            }
            if let link = run.link, !link.absoluteString.contains("STUDYSIDEMATH"), ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                html = "<a href=\"" + escapeHTML(link.absoluteString) + "\">" + html + "</a>"
            }
            return html
        }.joined()
    }

    static func html(_ source: String) -> String {
        let document = MathFormatting.protect(source)
        var html = blocks(document.text).map { block -> String in
            let text = inlineHTML(block.source)
            switch block.kind {
            case .paragraph: return "<p>" + text + "</p>"
            case .heading(let level): return "<h\(level)>" + text + "</h\(level)>"
            case .list(let marker): return "<div class=\"list-item\"><span class=\"marker\">" + escapeHTML(marker) + " </span><span>" + text + "</span></div>"
            case .quote: return "<blockquote>" + text + "</blockquote>"
            case .code: return "<pre><code>" + escapeHTML(block.source) + "</code></pre>"
            case .divider: return "<hr>"
            }
        }.joined(separator: "\n")
        for formula in document.formulas {
            let tag = "<span class=\"math\" data-display=\"\(formula.display)\" data-tex=\"" + escapeHTML(formula.tex) + "\" data-plain=\"" + escapeHTML(MathFormatting.plain(formula.tex)) + "\">" + escapeHTML(MathFormatting.plain(formula.tex)) + "</span>"
            html = html.replacingOccurrences(of: formula.token, with: tag)
        }
        return html
    }
}

/// Answer documents expand to their full height. Vertical scrolling belongs to the chat.
@MainActor enum AnswerScrolling {
    static func scroll(from view: NSView, action: String, delta: Double = 0, mode: Int = 0) {
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? NSScrollView, let document = scroll.documentView {
                let clip = scroll.contentView
                let minimum = document.bounds.minY
                let maximum = max(minimum, document.bounds.maxY - clip.bounds.height)
                let page = max(1, clip.bounds.height * 0.85)
                let direction: CGFloat = document.isFlipped ? 1 : -1
                var origin = clip.bounds.origin
                switch action {
                case "wheel":
                    guard delta.isFinite, (0...2).contains(mode) else { return }
                    let scale: CGFloat = mode == 1 ? 16 : mode == 2 ? page : 1
                    origin.y += direction * CGFloat(max(-4000, min(4000, delta))) * scale
                case "pageDown": origin.y += direction * page
                case "pageUp": origin.y -= direction * page
                case "home": origin.y = document.isFlipped ? minimum : maximum
                case "end": origin.y = document.isFlipped ? maximum : minimum
                default: return
                }
                origin.y = min(maximum, max(minimum, origin.y))
                clip.scroll(to: origin)
                scroll.reflectScrolledClipView(clip)
                return
            }
            ancestor = current.superview
        }
    }
}

/// A single document per answer lets macOS select text across headings, lists, formulas and paragraphs.
struct AnswerDocumentView: NSViewRepresentable {
    let source: String
    let theme: StudyTheme
    @Binding var height: CGFloat

    static var resourceDirectory: URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("AnswerRenderer"),
           FileManager.default.fileExists(atPath: url.appendingPathComponent("answer.html").path) { return url }
        #if PREVIEW
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/AnswerRenderer")
        #else
        return nil
        #endif
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "answerHeight")
        config.userContentController.add(context.coordinator, name: "answerScroll")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        if let directory = Self.resourceDirectory {
            view.loadFileURL(directory.appendingPathComponent("answer.html"), allowingReadAccessTo: directory)
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "answerHeight")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "answerScroll")
        view.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AnswerDocumentView
        var ready = false
        var lastSource: String?
        var lastTheme: StudyTheme?
        init(_ parent: AnswerDocumentView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ view: WKWebView) {
            guard ready, lastSource != parent.source || lastTheme != parent.theme else { return }
            lastSource = parent.source; lastTheme = parent.theme
            let color = NSColor(parent.theme.ink).usingColorSpace(.deviceRGB) ?? .labelColor
            let accent = NSColor(parent.theme.accent).usingColorSpace(.deviceRGB) ?? .linkColor
            func css(_ c: NSColor) -> String { "rgb(\(Int(c.redComponent * 255)),\(Int(c.greenComponent * 255)),\(Int(c.blueComponent * 255)))" }
            let style = ["color": css(color), "accent": css(accent), "font": parent.theme == .editorial ? "Georgia, serif" : "-apple-system, BlinkMacSystemFont, sans-serif"]
            view.callAsyncJavaScript("window.updateAnswer(html, style)", arguments: ["html": AnswerFormatting.html(parent.source), "style": style], in: nil, in: .page) { _ in }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame else { return }
            if message.name == "answerScroll" {
                guard let body = message.body as? [String: Any], let action = body["action"] as? String,
                      let view = message.webView else { return }
                AnswerScrolling.scroll(from: view, action: action, delta: body["delta"] as? Double ?? 0, mode: body["mode"] as? Int ?? 0)
                return
            }
            guard message.name == "answerHeight", let value = message.body as? Double, value.isFinite, value >= 0 else { return }
            let newHeight = max(24, ceil(value))
            guard abs(parent.height - newHeight) > 0.5 else { return }
            parent.height = newHeight
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else if navigationAction.request.url?.isFileURL == true { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
    }
}
