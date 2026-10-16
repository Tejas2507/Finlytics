import SwiftUI

/// Lightweight block-level markdown renderer for chat bubbles.
///
/// `AttributedString(markdown:)` only supports inline styling, so LLM output
/// like "- item" or "1. step" would render as literal dashes. This view adds a
/// small block layer (paragraphs, headings, bullets, numbered lists, fenced
/// code, dividers) while delegating inline styles (bold, italics, code, links)
/// to the system parser.
struct ChatMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Blocks

    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bullet(text: String, depth: Int)
        case numbered(marker: String, text: String, depth: Int)
        case code(String)
        case divider
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var codeBuffer: [String]?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                if let buffer = codeBuffer {
                    blocks.append(.code(buffer.joined(separator: "\n")))
                    codeBuffer = nil
                } else {
                    codeBuffer = []
                }
                continue
            }

            if codeBuffer != nil {
                codeBuffer?.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if let heading = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            let depth = min(rawLine.prefix { $0 == " " || $0 == "\t" }.count / 2, 2)

            if let bulletText = bulletMatch(trimmed) {
                flushParagraph()
                blocks.append(.bullet(text: bulletText, depth: depth))
                continue
            }

            if let numbered = numberedMatch(trimmed) {
                flushParagraph()
                blocks.append(.numbered(marker: numbered.marker, text: numbered.text, depth: depth))
                continue
            }

            paragraphLines.append(trimmed)
        }

        // An unterminated fence (common while streaming) still renders as code.
        if let buffer = codeBuffer, !buffer.isEmpty {
            blocks.append(.code(buffer.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...4).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes.count, text)
    }

    private static func bulletMatch(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            let text = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numberedMatch(_ line: String) -> (marker: String, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 2 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        let text = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (String(digits), text)
    }

    // MARK: - Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 2)
        case .bullet(let text, let depth):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                inlineText(text)
            }
            .padding(.leading, CGFloat(depth) * 14)
        case .numbered(let marker, let text, let depth):
            HStack(alignment: .top, spacing: 8) {
                Text("\(marker).")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                inlineText(text)
            }
            .padding(.leading, CGFloat(depth) * 14)
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(10)
            }
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        case .divider:
            Divider().opacity(0.5)
        }
    }

    private func inlineText(_ string: String) -> some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: string,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
            } else {
                Text(string)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
