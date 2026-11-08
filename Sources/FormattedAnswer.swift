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
        blocks(source).map { block in
            let text = String(block.attributed.characters)
            switch block.kind {
            case .list(let marker): return marker + " " + text
            case .divider: return ""
            default: return text
            }
        }.joined(separator: "\n\n")
    }
}

struct FormattedAnswer: View {
    let source: String
    @Environment(\.studyTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AnswerFormatting.blocks(source)) { block in
                switch block.kind {
                case .heading(let level):
                    Text(block.attributed)
                        .font(.system(size: level <= 2 ? 16 : 14, weight: .semibold, design: theme.design))
                        .padding(.top, block.id == 0 ? 0 : 3)
                case .list(let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(theme.accent).frame(minWidth: 12, alignment: .leading)
                        Text(block.attributed).frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .quote:
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1).fill(theme.accent.opacity(0.35)).frame(width: 2)
                        Text(block.attributed).foregroundStyle(theme.ink.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading)
                    }.fixedSize(horizontal: false, vertical: true)
                case .code:
                    Text(block.source).font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(theme.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                case .divider:
                    Rectangle().fill(theme.border).frame(height: 1).padding(.vertical, 3)
                case .paragraph:
                    Text(block.attributed).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 13, design: theme.design)).lineSpacing(5)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
    }
}
