// filepath: NoesisNoema/Shared/RAG/Citations.swift
// Comments: English

import Foundation

struct CitationInfo: Codable, Hashable {
    let index: Int // 1-based label index [1], [2], ...
    let title: String?
    let path: String?
    let page: Int?
}

struct ParagraphCitations: Codable, Hashable {
    /// paragraph index (0-based) to citation label indexes
    let perParagraph: [[Int]]
    /// catalog of citation infos (by index)
    let catalog: [CitationInfo]
}

enum CitationExtractor {
    /// Extracts paragraph-wise citation indices from the answer text.
    /// - Returns: per-paragraph arrays of 1-based label numbers
    static func extractParagraphLabels(from answer: String) -> [[Int]] {
        let paragraphs = splitParagraphs(answer)
        let regex = try! NSRegularExpression(pattern: "\\[(\\d+)\\]", options: [])
        return paragraphs.map { p in
            let ns = p as NSString
            let matches = regex.matches(in: p, options: [], range: NSRange(location: 0, length: ns.length))
            var nums: [Int] = []
            for m in matches {
                if m.numberOfRanges > 1 {
                    let g = ns.substring(with: m.range(at: 1))
                    if let n = Int(g) { nums.append(n) }
                }
            }
            // de-duplicate while preserving order
            var seen = Set<Int>()
            return nums.filter { seen.insert($0).inserted }
        }
    }
    static func splitParagraphs(_ text: String) -> [String] {
        // Group lines by blank-line separators into paragraphs
        let lines = text.components(separatedBy: "\n")
        var paras: [String] = []
        var current: [String] = []
        func flush() {
            let joined = current.joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !joined.isEmpty { paras.append(joined) }
            current.removeAll(keepingCapacity: true)
        }
        for line in lines {
            if line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                if !current.isEmpty { flush() }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { flush() }
        return paras
    }
}
