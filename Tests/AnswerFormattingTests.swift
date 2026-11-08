import Foundation

@main struct AnswerFormattingTests {
    static func main() {
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
        print("PASS: headings, emphasis, lists, quotes, copied plain text, literal maths, code and incomplete fences")
    }
}
