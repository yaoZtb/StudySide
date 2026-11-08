import Foundation

/// Protect TeX before Markdown can consume backslashes or underscores.
enum MathFormatting {
    struct Formula {
        let token: String
        let tex: String
        let display: Bool
    }
    struct Document {
        let text: String
        let formulas: [Formula]
    }
    static func protect(_ source: String) -> Document {
        // Fenced and inline code are matched first and left untouched.
        let pattern = #"(`{3,}[\s\S]*?(?:`{3,}|$)|~{3,}[\s\S]*?(?:~{3,}|$)|`[^`\n]*`)|\\\[([\s\S]*?)\\\]|\\\(([\s\S]*?)\\\)|(?<!\\)\$\$([\s\S]*?)(?<!\\)\$\$|(?<![\\$])\$(?![\s$])([^\n]*?\S)(?<!\\)\$(?![\d$])|(?m:^\[\s*\n)([\s\S]*?)(?m:^\]\s*$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return Document(text: source, formulas: []) }
        let ns = source as NSString
        var result = "", end = 0, formulas: [Formula] = []
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: end, length: match.range.location - end))
            let original = ns.substring(with: match.range)
            if match.range(at: 1).location != NSNotFound { result += original }
            else if let group = (2...6).first(where: { match.range(at: $0).location != NSNotFound }) {
                let tex = ns.substring(with: match.range(at: group)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Repair bracket-only display delimiters only when the content actually contains TeX.
                if group == 6 && tex.range(of: #"\\[A-Za-z]+"#, options: .regularExpression) == nil { result += original }
                else {
                    let token = "STUDYSIDEMATH" + salt + "N" + String(formulas.count) + "END"
                    formulas.append(Formula(token: token, tex: tex, display: group == 2 || group == 4 || group == 6))
                    result += token
                }
            }
            end = NSMaxRange(match.range)
        }
        result += ns.substring(from: end)
        return Document(text: result, formulas: formulas)
    }

    /// Readable clipboard/export fallback; on-screen layout is handled by KaTeX.
    static func plain(_ tex: String) -> String {
        let commands: [String: String] = [
            "longrightarrow":"⟶", "rightarrow":"→", "to":"→", "longleftarrow":"⟵", "leftarrow":"←", "leftrightarrow":"↔", "Rightarrow":"⇒", "Longrightarrow":"⟹",
            "alpha":"α", "beta":"β", "gamma":"γ", "delta":"δ", "theta":"θ", "lambda":"λ", "mu":"μ", "pi":"π", "sigma":"σ", "omega":"ω", "Delta":"Δ", "Omega":"Ω",
            "times":"×", "cdot":"·", "pm":"±", "le":"≤", "leq":"≤", "ge":"≥", "geq":"≥", "ne":"≠", "neq":"≠", "approx":"≈", "infty":"∞", "sum":"∑", "int":"∫", "partial":"∂", "nabla":"∇", "in":"∈", "notin":"∉", "forall":"∀", "exists":"∃", "ldots":"…", "dots":"…", "cdots":"⋯", "quad":" ", "qquad":"  ", "land":"∧", "lor":"∨", "neg":"¬"
        ]
        let chars = Array(tex)
        var i = 0
        func group() -> String {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            if i < chars.count && chars[i] == "{" { i += 1; return parse(stop: "}") }
            if i < chars.count { let value = String(chars[i]); i += 1; return value }
            return ""
        }
        func script(_ value: String, upper: Bool) -> String {
            let from = Array("0123456789+-=()in")
            let to = Array(upper ? "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁱⁿ" : "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ᵢₙ")
            let map = Dictionary(uniqueKeysWithValues: zip(from, to))
            if value.allSatisfy({ map[$0] != nil }) { return String(value.compactMap { map[$0] }) }
            return (upper ? "^" : "_") + (value.count > 1 ? "(" + value + ")" : value)
        }
        func parse(stop: Character? = nil) -> String {
            var output = ""
            while i < chars.count {
                let c = chars[i]; i += 1
                if c == stop { break }
                if c == "{" { output += parse(stop: "}"); continue }
                if c == "_" || c == "^" { output += script(group(), upper: c == "^"); continue }
                if c != "\\" { output.append(c); continue }
                guard i < chars.count else { output += "\\"; break }
                if !chars[i].isLetter {
                    let escaped = chars[i]; i += 1
                    if [";", ",", ":", " "].contains(escaped) { output += " " }
                    else if escaped == "!" {} else if escaped == "\\" { output += "\n" } else { output.append(escaped) }
                    continue
                }
                let start = i
                while i < chars.count && chars[i].isLetter { i += 1 }
                let name = String(chars[start..<i])
                switch name {
                case "frac", "dfrac", "tfrac": let a = group(); let b = group(); output += "(" + a + ")/(" + b + ")"
                case "sqrt": output += "√(" + group() + ")"
                case "text", "textrm", "textbf", "mathrm", "mathbf", "mathit", "operatorname", "mathsf", "mathcal": output += group()
                case "left", "right", "displaystyle", "textstyle", "limits": break
                default: output += commands[name] ?? ("\\" + name)
                }
            }
            return output
        }
        return parse().replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
