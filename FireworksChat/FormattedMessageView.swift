import SwiftUI

struct FormattedMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseSegments().enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .plain(let content):
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(content)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                case .code(let language, let content):
                    codeBlockView(language: language, code: content)
                }
            }
        }
    }

    // MARK: - Code Block View

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lang = language, !lang.isEmpty {
                Text(lang)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, language == nil ? 10 : 6)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Parsing

    private enum Segment {
        case plain(String)
        case code(language: String?, content: String)
    }

    private func parseSegments() -> [Segment] {
        let delimiter = "```"
        let parts = text.components(separatedBy: delimiter)

        // If no delimiter found, return entire text as plain
        if parts.count == 1 {
            return [.plain(text)]
        }

        var segments: [Segment] = []

        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                // Even indices are plain text
                if !part.isEmpty {
                    segments.append(.plain(part))
                }
            } else {
                // Odd indices are code blocks
                let (language, code) = extractLanguage(from: part)
                segments.append(.code(language: language, content: code))
            }
        }

        return segments
    }

    private func extractLanguage(from block: String) -> (String?, String) {
        // Find the first newline to check for a language identifier
        guard let newlineIndex = block.firstIndex(of: "\n") else {
            // No newline — the entire block could be a language tag with no code,
            // or a single line of code. If it has no spaces, treat as language with empty code.
            let trimmed = block.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.contains(" ") {
                return (trimmed, "")
            }
            return (nil, block)
        }

        let firstLine = String(block[block.startIndex..<newlineIndex])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(block[block.index(after: newlineIndex)...])

        // If first line looks like a language identifier (no spaces, reasonably short)
        if !firstLine.isEmpty && !firstLine.contains(" ") && firstLine.count <= 20 {
            return (firstLine, rest)
        }

        // Otherwise treat the whole block as code with no language
        return (nil, block)
    }
}
