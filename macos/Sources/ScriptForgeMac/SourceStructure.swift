import Foundation

struct SourceBoundary: Hashable, Sendable {
    let range: NSRange
    let number: Int
    let title: String
}

struct SourceStructureAnalysis: Hashable, Sendable {
    let kind: SourceContentKind
    let episodeBoundaries: [SourceBoundary]
    let chapterBoundaries: [SourceBoundary]
    let sceneHeadingCount: Int
    let screenplayMarkerCount: Int
    let dialogueLineCount: Int
    let diagnostics: [SourceDiagnostic]
}

enum SourceStructureDetector {
    static let ordinalCharacters = "0-9一二三四五六七八九十百千零两〇"

    private static let episodePattern =
        #"^(?:#{1,6}[ \t]*)?(?:第[ \t]*([0-9一二三四五六七八九十百千零两〇]+)[ \t]*(?:集|回|话)(?:[ \t]*[:：\-—·]?[ \t]*)(.*)|(?:EP(?:ISODE)?\.?|E)[ \t]*0*([0-9]+)(?:[ \t]*[:：\-—·.]?[ \t]*)(.*))$"#
    private static let chapterPattern =
        #"^(?:#{1,6}[ \t]*)?(?:第[ \t]*([0-9一二三四五六七八九十百千零两〇]+)[ \t]*(?:章|节)(?:[ \t]*[:：\-—·]?[ \t]*)(.*)|CHAPTER[ \t]*0*([0-9]+)(?:[ \t]*[:：\-—·.]?[ \t]*)(.*))$"#
    private static let scenePattern =
        #"^(?:(?:场次|场景|SCENE)\s*[0-9一二三四五六七八九十百千零两〇]+\s*[:：.]?.*|(?:\d+\s*[.、)]\s*)?(?:内景|外景|内外景|INT\.?|EXT\.?|INT\.?/EXT\.?|I/E)(?:\s|[.．\-—]).*)$"#
    private static let markerPattern =
        #"^[\[【（(]?\s*(?:画面|对白|台词|动作|旁白|钩子|卡点|转场|镜头|ACTION|VISUAL|DIALOGUE|NARRATION|HOOK|TRANSITION|SHOT)\s*[\]】）)]?\s*[:：]?$"#

    static func analyze(_ text: String) -> SourceStructureAnalysis {
        let episodes = boundaries(pattern: episodePattern, in: text)
        let chapters = boundaries(pattern: chapterPattern, in: text)
        let lines = text.components(separatedBy: "\n")
        let sceneHeadingCount = lines.filter { matches(scenePattern, line: $0) }.count
        let markerCount = lines.filter { matches(markerPattern, line: $0) }.count
        let dialogueCount = lines.filter(isDialogueLine).count

        let hasEpisodeStructure = !episodes.isEmpty
        let hasScreenplayBody = sceneHeadingCount > 0 || markerCount >= 2 || dialogueCount >= 3
        let standaloneScreenplay = episodes.isEmpty && sceneHeadingCount >= 2 && dialogueCount >= 2
        let kind: SourceContentKind = (hasEpisodeStructure && hasScreenplayBody) || standaloneScreenplay
            ? .screenplay
            : .prose

        var diagnostics: [SourceDiagnostic] = []
        if kind == .screenplay {
            diagnostics += sequenceDiagnostics(episodes.map(\.number))
            if sceneHeadingCount == 0 {
                diagnostics.append(SourceDiagnostic(
                    id: "screenplay-no-scene-headings",
                    severity: .warning,
                    code: "screenplay.no_scene_headings",
                    message: "检测到分集剧本，但没有明确场次标题；每集将使用安全的单场回退结构。",
                    unitNumbers: episodes.map(\.number)
                ))
            }
            if markerCount == 0 {
                diagnostics.append(SourceDiagnostic(
                    id: "screenplay-unlabeled-blocks",
                    severity: .info,
                    code: "screenplay.unlabeled_blocks",
                    message: "剧本未使用画面/对白等区块标签，将依据场次标题和说话人格式解析。",
                    unitNumbers: []
                ))
            }
            if episodes.isEmpty {
                diagnostics.append(SourceDiagnostic(
                    id: "screenplay-single-unit",
                    severity: .info,
                    code: "screenplay.single_unit",
                    message: "检测到未分集的剧本格式，已作为单个内容单元导入。",
                    unitNumbers: [1]
                ))
            }
        } else if !episodes.isEmpty {
            diagnostics.append(SourceDiagnostic(
                id: "episode-prose-classification",
                severity: .info,
                code: "source.episodic_prose",
                message: "检测到分集标题，但正文缺少场次或对白结构，已按故事文本导入。",
                unitNumbers: episodes.map(\.number)
            ))
        }

        return SourceStructureAnalysis(
            kind: kind,
            episodeBoundaries: episodes,
            chapterBoundaries: chapters,
            sceneHeadingCount: sceneHeadingCount,
            screenplayMarkerCount: markerCount,
            dialogueLineCount: dialogueCount,
            diagnostics: diagnostics
        )
    }

    static func parseOrdinal(_ value: String) -> Int? {
        let normalized = value
            .replacingOccurrences(of: "两", with: "二")
            .replacingOccurrences(of: "〇", with: "零")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(normalized) { return number }

        let digits: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        ]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1_000]
        var total = 0
        var current = 0
        var sawValue = false
        for character in normalized {
            if let digit = digits[character] {
                current = digit
                sawValue = true
            } else if let unit = units[character] {
                total += max(1, current) * unit
                current = 0
                sawValue = true
            } else {
                return nil
            }
        }
        return sawValue ? total + current : nil
    }

    static func isSceneHeading(_ line: String) -> Bool {
        matches(scenePattern, line: line)
    }

    static func isScreenplayMarker(_ line: String) -> Bool {
        matches(markerPattern, line: line)
    }

    static func isDialogueLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0 == "：" || $0 == ":" }) else {
            return false
        }
        let speaker = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
        let text = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
        guard (1...24).contains(speaker.count), !text.isEmpty else { return false }
        let metadata = [
            "作者", "简介", "内容简介", "位置", "情绪", "情绪强度", "关键词", "人物",
            "场次", "场景", "画面", "对白", "台词", "钩子", "卡点", "备注", "题材", "类型",
            "ACTION", "VISUAL", "DIALOGUE", "NARRATION", "HOOK", "TRANSITION", "SHOT",
        ]
        return !metadata.contains { speaker == $0 || speaker.hasPrefix($0 + " ") }
    }

    private static func boundaries(pattern: String, in text: String) -> [SourceBoundary] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines, .caseInsensitive]
        ) else { return [] }
        let nsText = text as NSString
        return regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ).compactMap { match in
            let ordinalRange = match.range(at: 1).location != NSNotFound
                ? match.range(at: 1)
                : match.range(at: 3)
            guard ordinalRange.location != NSNotFound,
                  let number = parseOrdinal(nsText.substring(with: ordinalRange)) else {
                return nil
            }
            let titleRange = match.range(at: 2).location != NSNotFound
                ? match.range(at: 2)
                : match.range(at: 4)
            let title = titleRange.location == NSNotFound
                ? ""
                : cleanTitle(nsText.substring(with: titleRange))
            return SourceBoundary(range: match.range, number: number, title: title)
        }
    }

    private static func cleanTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "《》[]【】"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ pattern: String, line: String) -> Bool {
        line.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func sequenceDiagnostics(_ numbers: [Int]) -> [SourceDiagnostic] {
        guard !numbers.isEmpty else { return [] }
        var diagnostics: [SourceDiagnostic] = []
        let duplicates = Dictionary(grouping: numbers, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        if !duplicates.isEmpty {
            diagnostics.append(SourceDiagnostic(
                id: "duplicate-episodes-\(duplicates.map(String.init).joined(separator: "-"))",
                severity: .error,
                code: "screenplay.duplicate_episode_numbers",
                message: "发现重复集号：\(duplicates.map(String.init).joined(separator: "、"))。",
                unitNumbers: duplicates
            ))
        }

        let orderedUnique = Array(Set(numbers)).sorted()
        if let first = orderedUnique.first, let last = orderedUnique.last, first < last {
            let missing = Array(first...last).filter { !orderedUnique.contains($0) }
            if !missing.isEmpty {
                diagnostics.append(SourceDiagnostic(
                    id: "missing-episodes-\(missing.map(String.init).joined(separator: "-"))",
                    severity: .warning,
                    code: "screenplay.missing_episode_numbers",
                    message: "集号不连续，缺少第 \(missing.map(String.init).joined(separator: "、")) 集。",
                    unitNumbers: missing
                ))
            }
        }

        if zip(numbers, numbers.dropFirst()).contains(where: { $1 <= $0 }) {
            diagnostics.append(SourceDiagnostic(
                id: "episodes-out-of-order",
                severity: .warning,
                code: "screenplay.episode_order",
                message: "部分集号顺序异常，请在生成分镜前复核。",
                unitNumbers: numbers
            ))
        }
        return diagnostics
    }
}
