import SwiftUI

/// Renders a chat message with mixed plain text, markdown inline formatting,
/// and fenced code blocks (```lang ... ```).
struct FormattedMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseSegments().enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let content):
                    markdownView(content)
                case .code(let language, let content):
                    codeBlockView(language: language, code: content)
                }
            }
        }
    }

    // MARK: - Inline rendering

    @ViewBuilder
    private func markdownView(_ content: String) -> some View {
        let lines = content.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                lineView(raw)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        // Headings
        if raw.hasPrefix("### ") {
            Text(attributed(String(raw.dropFirst(4))))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if raw.hasPrefix("## ") {
            Text(attributed(String(raw.dropFirst(3))))
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if raw.hasPrefix("# ") {
            Text(attributed(String(raw.dropFirst(2))))
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if let bullet = bulletPrefix(raw) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundColor(.secondary)
                Text(attributed(bullet))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty line — small spacer
            Spacer().frame(height: 2)
        } else {
            Text(attributed(raw))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func bulletPrefix(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
        if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
        return nil
    }

    /// Convert a markdown line into AttributedString. Falls back to plain text
    /// if parsing fails. Uses inline-only mode so newlines are preserved.
    private func attributed(_ line: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: line,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(line)
        }
    }

    // MARK: - Code Block View

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Parsing

    private enum Segment {
        case markdown(String)
        case code(language: String?, content: String)
    }

    private func parseSegments() -> [Segment] {
        let delimiter = "```"
        let parts = text.components(separatedBy: delimiter)
        if parts.count == 1 {
            return [.markdown(text)]
        }
        var segments: [Segment] = []
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                if !part.isEmpty {
                    segments.append(.markdown(part))
                }
            } else {
                let (language, code) = extractLanguage(from: part)
                segments.append(.code(language: language, content: code))
            }
        }
        return segments
    }

    private func extractLanguage(from block: String) -> (String?, String) {
        guard let newlineIndex = block.firstIndex(of: "\n") else {
            let trimmed = block.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.contains(" ") {
                return (trimmed, "")
            }
            return (nil, block)
        }
        let firstLine = String(block[block.startIndex..<newlineIndex])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(block[block.index(after: newlineIndex)...])
        if !firstLine.isEmpty && !firstLine.contains(" ") && firstLine.count <= 20 {
            return (firstLine, rest)
        }
        return (nil, block)
    }
}
