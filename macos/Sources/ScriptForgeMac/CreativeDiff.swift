import Foundation

enum ParagraphDiffKind: String, Hashable, Sendable {
    case unchanged
    case added
    case removed
}

struct ParagraphDiffEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: ParagraphDiffKind
    let text: String
}

enum CreativeParagraphDiff {
    static func compare(_ original: String, _ revised: String) -> [ParagraphDiffEntry] {
        let left = paragraphs(original)
        let right = paragraphs(revised)
        let rows = left.count + 1
        let columns = right.count + 1
        var table = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        if !left.isEmpty && !right.isEmpty {
            for i in stride(from: left.count - 1, through: 0, by: -1) {
                for j in stride(from: right.count - 1, through: 0, by: -1) {
                    table[i][j] = left[i] == right[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var result: [ParagraphDiffEntry] = []
        var i = 0
        var j = 0
        while i < left.count || j < right.count {
            if i < left.count, j < right.count, left[i] == right[j] {
                result.append(ParagraphDiffEntry(id: UUID(), kind: .unchanged, text: left[i]))
                i += 1
                j += 1
            } else if j < right.count, i == left.count || table[i][j + 1] >= table[i + 1][j] {
                result.append(ParagraphDiffEntry(id: UUID(), kind: .added, text: right[j]))
                j += 1
            } else if i < left.count {
                result.append(ParagraphDiffEntry(id: UUID(), kind: .removed, text: left[i]))
                i += 1
            }
        }
        return result
    }

    private static func paragraphs(_ value: String) -> [String] {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
