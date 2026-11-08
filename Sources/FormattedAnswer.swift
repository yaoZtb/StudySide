import SwiftUI

enum AnswerFormatting {
    struct Block: Identifiable {
        enum Kind: Equatable {
            case paragraph, heading(Int), list(String), quote, code, divider
        }
        let id: Int
        let kind: Kind
        let source: String
        var attributed: AttributedString {
            if kind == .code { return AttributedString(source) }
            return AnswerFormatting.inline(source)
        }
    }

    static func inline(_ source: String) -> AttributedString {
        // Native Markdown parsing preserves literal maths, escaped symbols and code.
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
    }

    static func blocks(_ source: String) -> [Block] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        var fence: String?
        func add(_ kind: Block.Kind, _ text: String) {
            result.append(Block(id: result.count, kind: kind, source: text))
        }
        func flush() {
            if !paragraph.isEmpty { add(.paragraph, paragraph.joined(separator: "\n")); paragraph.removeAll() }
        }
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if var current = code {
                if let fence, trimmed.hasPrefix(fence), trimmed.dropFirst(fence.count).allSatisfy({ $0 == fence.first || $0.isWhitespace }) {
                    add(.code, current.joined(separator: "\n")); code = nil
                } else { current.append(raw); code = current }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let marker = trimmed.first!
                fence = String(trimmed.prefix(while: { $0 == marker }))
                code = []
                continue
            }
            if trimmed.isEmpty { flush(); continue }
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first?.isWhitespace == true {
                flush()
                var title = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                if let closing = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) { title.removeSubrange(closing) }
                add(.heading(hashes), title)
            } else if ["---", "***", "___", "* * *", "- - -"].contains(trimmed) {
                flush(); add(.divider, "")
            } else if let marker = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flush(); add(.list("•"), String(trimmed[marker.upperBound...]))
            } else if let marker = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flush()
                let prefix = String(trimmed[..<marker.upperBound]).trimmingCharacters(in: .whitespaces)
                add(.list(prefix), String(trimmed[marker.upperBound...]))
            } else if trimmed.hasPrefix("> ") {
                flush(); add(.quote, String(trimmed.dropFirst(2)))
            } else {
                paragraph.append(raw)
            }
        }
        flush()
        if let code { add(.code, code.joined(separator: "\n")) }
        return result
    }

    static func plainText(_ source: String) -> String {
        let document = MathFormatting.protect(source)
        var result = blocks(document.text).map { block in
            let text = String(block.attributed.characters)
            switch block.kind {
            case .list(let marker): return marker + " " + text
            case .divider: return ""
            default: return text
            }
        }.joined(separator: "\n\n")
        for formula in document.formulas {
            result = result.replacingOccurrences(of: formula.token, with: MathFormatting.plain(formula.tex))
        }
        return result
    }
}

struct FormattedAnswer: View {
    let source: String
    @Environment(\.studyTheme) private var theme
    @State private var height: CGFloat = 24
    var body: some View {
        AnswerDocumentView(source: source, theme: theme, height: $height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
    }
}
