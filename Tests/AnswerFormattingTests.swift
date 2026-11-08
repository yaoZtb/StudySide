import Foundation
import AppKit
import WebKit

@main @MainActor struct AnswerFormattingTests {
    static func main() async throws {
        let sample = """
        # 条件概率
        **核心结论**：已知 B，重新计算 A。
        * 第一点：缩小样本空间
        - 第二点：计算比例
        1. 先看 B
        > 注意条件
        """
        let blocks = AnswerFormatting.blocks(sample)
        precondition(blocks.first?.kind == .heading(1))
        precondition(blocks.contains { $0.kind == .list("•") })
        let plain = AnswerFormatting.plainText(sample)
        precondition(!plain.contains("# 条件") && !plain.contains("**") && !plain.contains("* 第"))
        precondition(plain.contains("核心结论") && plain.contains("• 第一点") && plain.contains("1. 先看"))
        for literal in ["a * b = c", "x**2", "C# 与 #标签", "#include <stdio.h>", "a_b_c"] {
            precondition(AnswerFormatting.plainText(literal) == literal, "Literal changed: " + literal)
        }
        let code = "```python\n# comment\na * b\n```"
        let codeBlocks = AnswerFormatting.blocks(code)
        precondition(codeBlocks.count == 1 && codeBlocks[0].kind == .code)
        precondition(AnswerFormatting.plainText(code) == "# comment\na * b")
        precondition(AnswerFormatting.blocks("```\nunclosed").first?.kind == .code)
        let bold = AnswerFormatting.inline("**结论** 与 `x*y`")
        precondition(String(bold.characters) == "结论 与 x*y")
        precondition(AnswerFormatting.plainText("### 标题 ###") == "标题")
        let circuit = #"\[V_{\text{out}}\;\longrightarrow\;R_f\;\longrightarrow\;V_+\;\longrightarrow\;R_g\;\longrightarrow\;0.\]"#
        let copiedCircuit = AnswerFormatting.plainText(circuit)
        precondition(copiedCircuit.contains("V_(out)") && copiedCircuit.contains("⟶") && copiedCircuit.contains("V₊"))
        precondition(!copiedCircuit.contains("\\"))
        let repaired = "[\n" + #"V_{\text{out}}\longrightarrow R_f"# + "\n\n]"
        precondition(MathFormatting.protect(repaired).formulas.count == 1)
        precondition(MathFormatting.protect(#"The price is $10 and $20. Use `\(x\)` literally."#).formulas.isEmpty)
        precondition(AnswerFormatting.plainText("```tex\n" + circuit + "\n```") == circuit)
        precondition(MathFormatting.plain(#"\frac{1}{2} + x^2"#) == "(1)/(2) + x²")
        let dangerous = AnswerFormatting.html(#"<script>alert(1)</script> [bad](javascript:alert) \(\href{https://example.com}{x}\)"#)
        precondition(!dangerous.contains("<script>") && !dangerous.contains("href=\"javascript:"))
        try await rendererChecks(circuit: circuit)
        print("PASS: headings, emphasis, lists, quotes, copied plain text, literal maths, code and incomplete fences")
    }

    static func rendererChecks(circuit: String) async throws {
        let directory = AnswerDocumentView.resourceDirectory!
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 700), configuration: config)
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        web.loadFileURL(directory.appendingPathComponent("answer.html"), allowingReadAccessTo: directory)
        var ready = false
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("typeof window.updateAnswer === 'function' && typeof katex !== 'undefined'")) as? Bool == true { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(ready, "Offline renderer resources did not load")
        let sample = "## Circuit\n\nFirst paragraph with **bold text**.\n\n" + circuit + "\n\nSecond paragraph to select.\n\n- A list item\n- Another list item"
        _ = try await web.callAsyncJavaScript("window.updateAnswer(html, {color:'#242630',accent:'#34363d',font:'sans-serif'})", arguments: ["html": AnswerFormatting.html(sample)], in: nil, contentWorld: .page)
        let count = try await web.evaluateJavaScript("document.querySelectorAll('.katex').length") as! Int
        precondition(count == 1, "Circuit formula was not rendered")
        let errors = try await web.evaluateJavaScript("document.querySelectorAll('.math-error').length") as! Int
        precondition(errors == 0)
        let copied = try await web.evaluateJavaScript("""
        (() => {
          const range = document.createRange();
          range.setStart(document.querySelector('p').firstChild, 6);
          const last = document.querySelectorAll('p')[2].firstChild;
          range.setEnd(last, 16);
          const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
          return window.selectedAnswerText();
        })()
        """) as! String
        precondition(copied.hasPrefix("paragraph with bold text."), "Partial first paragraph was not copied")
        precondition(copied.contains("⟶") && copied.hasSuffix("Second paragraph"), "Selection did not cross formula and paragraph boundaries")
        precondition(!copied.contains("longrightarrow") && !copied.contains("STUDYSIDEMATH"))
        // Incoming streamed tokens should not clear an active text selection.
        _ = try await web.evaluateJavaScript("window.updateAnswer('<p>New streamed text</p>', {color:'#242630',accent:'#34363d',font:'sans-serif'})")
        let preserved = try await web.evaluateJavaScript("window.selectedAnswerText()") as! String
        precondition(preserved == copied)
        _ = try await web.evaluateJavaScript("window.getSelection().removeAllRanges()")
        try await Task.sleep(for: .milliseconds(100))
        let updated = try await web.evaluateJavaScript("document.getElementById('answer').textContent") as! String
        precondition(updated.contains("New streamed text"))
        // Unknown commands fall back to readable text, without injecting HTML or external resources.
        _ = try await web.callAsyncJavaScript("window.updateAnswer(html, {color:'#242630',accent:'#34363d',font:'sans-serif'})", arguments: ["html": AnswerFormatting.html(#"\(\unknowncommand{x}\)"#)], in: nil, contentWorld: .page)
        let fallbackCount = try await web.evaluateJavaScript("document.querySelectorAll('.math-error').length") as! Int
        precondition(fallbackCount == 1)
        print("PASS: offline KaTeX circuit rendering, cross-paragraph partial selection, formula clipboard text, streaming selection preservation and invalid-TeX fallback")
        window.contentView = nil
    }
}
