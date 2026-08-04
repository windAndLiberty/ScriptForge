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
        guard let raw = String(data: data, encoding: .utf8) else {
            throw NovelParserError.unreadable
        }
        return try parse(text: raw, fileName: fileName)
    }

    static func parse(text: String, fileName: String) throws -> NovelDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw NovelParserError.empty }

        let pattern = #"^第\s*([0-9一二三四五六七八九十百零两〇]+)\s*章(?:\s+|[:：]?)(.*)$"#
        let regex = try NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        )
        let nsText = normalized as NSString
        let matches = regex.matches(
            in: normalized,
            range: NSRange(location: 0, length: nsText.length)
        )
        let metadataEnd = matches.first?.range.location ?? 0
        let metadata = nsText.substring(with: NSRange(location: 0, length: metadataEnd))
        let title = firstMatch(#"《([^》]+)》"#, in: metadata)
            ?? fileName.replacingOccurrences(of: #"\.[^.]+$"#, with: "", options: .regularExpression)
        let author = firstMatch(#"(?:作者|作\s*者)\s*[:：]\s*([^\n]+)"#, in: metadata) ?? "未知"
        let intro = firstMatch(
            #"(?:简介|内容简介)\s*[:：]\s*([\s\S]*?)(?=\n(?:来源|状态)\s*[:：]|={5,}|$)"#,
            in: metadata
        ) ?? ""

        let chapters: [Chapter]
        if matches.isEmpty {
            chapters = [
                Chapter(
                    id: "chapter-1",
                    index: 1,
                    title: "正文",
                    content: normalized,
                    characterCount: compactCount(normalized)
                )
            ]
        } else {
            chapters = matches.enumerated().map { offset, match in
                let contentStart = match.range.location + match.range.length
                let contentEnd = offset + 1 < matches.count
                    ? matches[offset + 1].range.location
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
                let titleRange = match.range(at: 2)
                let chapterTitle = titleRange.location == NSNotFound
                    ? "第\(offset + 1)章"
                    : nsText.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                return Chapter(
                    id: "chapter-\(offset + 1)",
                    index: offset + 1,
                    title: chapterTitle.isEmpty ? "第\(offset + 1)章" : chapterTitle,
                    content: content,
                    characterCount: compactCount(content)
                )
            }
        }

        return NovelDocument(
            fileName: fileName,
            title: title,
            author: author.trimmingCharacters(in: .whitespaces),
            intro: intro.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: normalized,
            characterCount: compactCount(normalized),
            chapters: chapters
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
                    title: "\(chapter.title)（片段\(offset + 1)）",
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
