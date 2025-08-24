// filepath: Shared/RAG/CitationLabeler.swift
// Project: NoesisNoema
// File: CitationLabeler.swift
// Description: Build labeled context for citations and enforce per-paragraph citation presence.
// License: MIT License

import Foundation

struct CitationLabel {
    let index: Int
    let chunk: Chunk
}

enum CitationLabeler {
    /// Build labeled context string and label mapping from retrieved chunks.
    /// - Returns: (context, labels) where context embeds [n] labels alongside chunk content.
    static func labeledContext(from chunks: [Chunk], perChunkLimit: Int = 600) -> (String, [CitationLabel]) {
        guard !chunks.isEmpty else { return ("", []) }
        var lines: [String] = []
        var labels: [CitationLabel] = []
        lines.append("CITATION LABELS:")
        for (i, c) in chunks.enumerated() {
            let n = i + 1
            let text = c.content.replacingOccurrences(of: "\n", with: " ")
            let clipped = text.count > perChunkLimit ? String(text.prefix(perChunkLimit)) + "…" : text
            lines.append("[\(n)] \(clipped)")
            labels.append(CitationLabel(index: n, chunk: c))
        }
        return (lines.joined(separator: "\n"), labels)
    }

    /// Instruction block to enforce per-paragraph citations.
    static func citationRules() -> String {
        return """
        CITATION RULES:
        - Use only the numbered labels from the Context (e.g., [1], [2]).
        - Every paragraph in your answer must end with one or more labels, e.g., "... [1]" or "... [1][3]".
        - If multiple sources support a paragraph, chain labels without spaces like [2][4].
        - Do not invent labels; do not cite labels not present in the Context.
        - If the context is insufficient, say you don't know concisely, but still cite the most relevant label.
        """
    }

    /// Enforce that each paragraph ends with at least one valid citation label.
    /// - Parameters:
    ///   - text: model output
    ///   - maxLabel: maximum allowed label id (1..maxLabel)
    /// - Returns: corrected text
    static func enforceCitations(text: String, maxLabel: Int) -> String {
        guard maxLabel > 0 else { return text }
        // Normalize newlines and group lines into paragraphs separated by blank lines
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var paragraphs: [String] = []
        var current: [String] = []
        for lineSub in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSub)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\n"))
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }

        var fixed: [String] = []
        let labelRegex = try! NSRegularExpression(pattern: #"\[(\d{1,2})\]"#, options: [])
        let tailRegex = try! NSRegularExpression(pattern: #"(\[(\d{1,2})\])+\s*$"#, options: [])
        for para in paragraphs {
            if para.isEmpty { fixed.append(para); continue }
            let fullRange = NSRange(para.startIndex..<para.endIndex, in: para)
            // Find all labels anywhere
            let matches = labelRegex.matches(in: para, options: [], range: fullRange)
            let validLabels: [String] = matches.compactMap { m in
                guard m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: para) else { return nil }
                if let n = Int(para[r]), n >= 1 && n <= maxLabel { return "[\(n)]" }
                return nil
            }
            // Check if paragraph already ends with label(s)
            let endsWithLabel = tailRegex.firstMatch(in: para, options: [], range: fullRange) != nil
            if validLabels.isEmpty {
                // Append fallback [1]
                fixed.append(para + " [1]")
            } else if !endsWithLabel {
                // Append the last seen valid label(s) at the end (dedup preserve order)
                var seen = Set<String>()
                let tail = validLabels.reversed().filter { seen.insert($0).inserted }.reversed().joined()
                fixed.append(para + " " + (tail.isEmpty ? "[1]" : tail))
            } else {
                fixed.append(para)
            }
        }
        return fixed.joined(separator: "\n\n")
    }
}
