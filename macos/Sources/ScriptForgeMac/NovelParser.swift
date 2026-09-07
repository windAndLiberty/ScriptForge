import Foundation

enum NovelParserError: LocalizedError {
    case empty
    case unreadable

    var errorDescription: String? {
        switch self {
        case .empty: "文件内容为空"
        case .unreadable: "无法按 UTF-8 读取文本"
        }
    }
}

enum NovelParser {
    static func parse(data: Data, fileName: String) throws -> NovelDocument {
        let raw: String
        do { raw = try DocumentImporter.decodePlainText(data) }
        catch { throw NovelParserError.unreadable }
        return try parse(text: raw, fileName: fileName)
    }

    static func parse(text: String, fileName: String) throws -> NovelDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw NovelParserError.empty }
        let sourceLanguage = AppLanguage.detect(in: normalized)

        let analysis = SourceStructureDetector.analyze(normalized)
        let boundaries: [SourceBoundary]
        if analysis.kind == .screenplay {
            boundaries = analysis.episodeBoundaries
        } else if !analysis.chapterBoundaries.isEmpty {
            boundaries = analysis.chapterBoundaries
        } else {
            boundaries = analysis.episodeBoundaries
        }
        let nsText = normalized as NSString
        let metadataEnd = boundaries.first?.range.location ?? 0
        let metadata = nsText.substring(with: NSRange(location: 0, length: metadataEnd))
        let title = firstMatch(#"《([^》]+)》"#, in: metadata)
            ?? fileName.replacingOccurrences(of: #"\.[^.]+$"#, with: "", options: .regularExpression)
        let author = firstMatch(#"(?:作者|作\s*者)\s*[:：]\s*([^\n]+)"#, in: metadata) ?? "未知"
        let intro = firstMatch(
            #"(?:简介|内容简介)\s*[:：]\s*([\s\S]*?)(?=\n(?:来源|状态)\s*[:：]|={5,}|$)"#,
            in: metadata
        ) ?? ""

        let chapters: [Chapter]
        if boundaries.isEmpty {
            chapters = [
                Chapter(
                    id: "chapter-1",
                    index: 1,
                    title: sourceLanguage == .english ? "Main Text" : "正文",
                    content: normalized,
                    characterCount: compactCount(normalized)
                )
            ]
        } else {
            chapters = boundaries.enumerated().map { offset, boundary in
                let contentStart = boundary.range.location + boundary.range.length
                let contentEnd = offset + 1 < boundaries.count
                    ? boundaries[offset + 1].range.location
                    : nsText.length
                let range = NSRange(
                    location: contentStart,
                    length: max(0, contentEnd - contentStart)
                )
                let content = nsText.substring(with: range)
                    .replacingOccurrences(
                        of: #"^-{5,}\s*$"#,
                        with: "",
                        options: [.regularExpression]
                    )
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackTitle = analysis.kind == .screenplay
                    ? (sourceLanguage == .english ? "Episode \(boundary.number)" : "第\(boundary.number)集")
                    : (sourceLanguage == .english ? "Chapter \(boundary.number)" : "第\(boundary.number)章")
                return Chapter(
                    id: analysis.kind == .screenplay
                        ? "episode-source-\(offset + 1)"
                        : "chapter-\(offset + 1)",
                    index: boundary.number,
                    title: boundary.title.isEmpty ? fallbackTitle : boundary.title,
                    content: content,
                    characterCount: compactCount(content)
                )
            }
        }

        var diagnostics = analysis.diagnostics
        let emptyUnits = chapters.filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !emptyUnits.isEmpty {
            diagnostics.append(SourceDiagnostic(
                id: "empty-source-units-\(emptyUnits.map { String($0.index) }.joined(separator: "-"))",
                severity: .warning,
                code: "source.empty_units",
                message: "以下内容单元没有正文：\(emptyUnits.map { String($0.index) }.joined(separator: "、"))。",
                unitNumbers: emptyUnits.map(\.index)
            ))
        }

        return NovelDocument(
            fileName: fileName,
            title: title,
            author: author.trimmingCharacters(in: .whitespaces),
            intro: intro.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: normalized,
            characterCount: compactCount(normalized),
            chapters: chapters,
            sourceKind: analysis.kind,
            diagnostics: diagnostics
        )
    }

    static func evidenceFragments(
        chapters: [Chapter],
        maxCharacters: Int = 12_000
    ) -> [Chapter] {
        chapters.flatMap { chapter in
            guard chapter.content.count > maxCharacters else { return [chapter] }
            var fragments: [String] = []
            var buffer = ""
            for paragraph in chapter.content.components(separatedBy: "\n") {
                if paragraph.count > maxCharacters {
                    if !buffer.isEmpty {
                        fragments.append(buffer)
                        buffer = ""
                    }
                    var start = paragraph.startIndex
                    while start < paragraph.endIndex {
                        let end = paragraph.index(start, offsetBy: maxCharacters, limitedBy: paragraph.endIndex)
                            ?? paragraph.endIndex
                        fragments.append(String(paragraph[start..<end]))
                        start = end
                    }
                } else if buffer.count + paragraph.count + 1 > maxCharacters {
                    fragments.append(buffer)
                    buffer = paragraph
                } else {
                    buffer += buffer.isEmpty ? paragraph : "\n" + paragraph
                }
            }
            if !buffer.isEmpty { fragments.append(buffer) }
            return fragments.enumerated().map { offset, content in
                Chapter(
                    id: chapter.id,
                    index: chapter.index,
                    title: AppLanguage.detect(in: content) == .english
                        ? "\(chapter.title) (Part \(offset + 1))"
                        : "\(chapter.title)（片段\(offset + 1)）",
                    content: content,
                    characterCount: compactCount(content)
                )
            }
        }
    }

    private static func compactCount(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard
            let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            ),
            match.numberOfRanges > 1,
            match.range(at: 1).location != NSNotFound
        else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }
}
