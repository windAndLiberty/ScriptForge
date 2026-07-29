import Foundation

enum OfflinePipeline {
    private struct Passage {
        let text: String
        let location: Int
    }

    static func run(
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions
    ) throws -> AdaptationResult {
        guard CharacterExtractor.validate(characters) else {
            throw PipelineError.invalidNames
        }
        let groups = group(document.chapters, count: options.episodeCount)
        let protagonist = characters.first?.targetName ?? "主角"
        let episodes = groups.enumerated().map { offset, chapters in
            buildEpisode(
                number: offset + 1,
                chapters: chapters,
                characters: characters,
                protagonist: protagonist,
                options: options
            )
        }
        let genre = document.rawText.range(
            of: #"系统|异能|觉醒|灵气"#,
            options: .regularExpression
        ) == nil ? options.genre : "都市异能·系统逆袭·热血轻喜"
        let facts = document.chapters.prefix(5).map {
            "第\($0.index)章：\(CharacterExtractor.applyRenames(firstAction(in: $0.content), characters: characters))"
        }
        let report = QualityEvaluator.evaluate(
            episodes: episodes,
            characters: characters,
            options: options
        )
        return AdaptationResult(
            logline: "\(protagonist)从人生低谷意外获得改变命运的能力，在一次次公开冲突中用机敏和行动完成逆袭，却也被卷入更大的危机。",
            genre: genre,
            themes: ["尊严与生存", "小人物逆袭", "能力与代价", "轻喜反转"],
            sourceFacts: facts,
            episodes: episodes,
            quality: report,
            generatedAt: Date(),
            mode: .offline
        )
    }

    private static func buildEpisode(
        number: Int,
        chapters: [Chapter],
        characters: [CharacterProfile],
        protagonist: String,
        options: AdaptationOptions
    ) -> Episode {
        let source = chapters.map(\.content).joined(separator: "\n")
        let quotes = quoted(in: source).map {
            CharacterExtractor.applyRenames($0.text, characters: characters)
        }
        let actions = actionLines(in: source).map {
            CharacterExtractor.applyRenames($0, characters: characters)
        }
        let sceneCount = max(2, options.scenesPerEpisode)
        let scenes = (0..<sceneCount).map { index in
            buildScene(
                episode: number,
                index: index,
                source: segment(source, index: index, count: sceneCount),
                characters: characters
            )
        }
        let title = chapters.first?.title
            .replacingOccurrences(of: #"[？！?!]+$"#, with: "", options: .regularExpression)
            ?? "命运转折"
        var episode = Episode(
            id: "episode-\(number)",
            number: number,
            title: String(title.prefix(18)),
            sourceChapterIDs: chapters.map(\.id),
            openingHook: quotes.first ?? "\(protagonist)被逼到退无可退，异变在此刻发生。",
            objective: actions.first ?? "\(protagonist)必须在公开冲突中夺回主动权。",
            reversal: quotes.dropFirst(2).first
                ?? "所有人以为\(protagonist)已经落败，他却亮出意想不到的底牌。",
            endHook: quotes.last ?? "更强的对手现身，直指\(protagonist)刚得到的秘密。",
            scenes: scenes,
            content: ""
        )
        episode.content = render(episode)
        return episode
    }

    private static func buildScene(
        episode: Int,
        index: Int,
        source: String,
        characters: [CharacterProfile]
    ) -> ScriptScene {
        let location = inferLocation(source)
        let quotes = quoted(in: source)
        let action = CharacterExtractor.applyRenames(
            actionLines(in: source).first
                ?? "局面骤然变化，众人的目光同时落在主角身上。",
            characters: characters
        )
        let fallback = characters.first?.targetName ?? "主角"
        var lines = Array(quotes.prefix(6).enumerated()).map { quoteIndex, quote in
            DialogueLine(
                speaker: inferSpeaker(
                    source: source,
                    position: quote.location,
                    characters: characters
                ) ?? fallback,
                text: CharacterExtractor.applyRenames(quote.text, characters: characters)
            )
        }
        if lines.count < 3 {
            let opponent = characters.dropFirst().first?.targetName ?? "对手"
            lines = [
                DialogueLine(speaker: fallback, text: "想让我认输？这才刚刚开始。"),
                DialogueLine(speaker: opponent, text: "你拿什么翻盘？"),
                DialogueLine(speaker: fallback, text: "就拿你最看不起的这一步。"),
            ]
        }
        return ScriptScene(
            id: "episode-\(episode)-scene-\(index + 1)",
            heading: location.heading,
            location: location.name,
            action: action,
            dialogue: lines
        )
    }

    static func render(_ episode: Episode) -> String {
        var lines = [
            "第\(episode.number)集《\(episode.title)》",
            "【本集目标】\(episode.objective)",
            "【冷开场】\(episode.openingHook)",
            "",
        ]
        for (index, scene) in episode.scenes.enumerated() {
            lines.append("\(index + 1). \(scene.heading) \(scene.location)")
            lines.append("△ \(scene.action)")
            lines.append(contentsOf: scene.dialogue.map { "\($0.speaker)：\($0.text)" })
            lines.append("")
        }
        lines.append("【反转】\(episode.reversal)")
        lines.append("【卡点】\(episode.endHook)")
        return lines.joined(separator: "\n")
    }

    private static func group(_ chapters: [Chapter], count: Int) -> [[Chapter]] {
        guard !chapters.isEmpty else { return [] }
        let groupCount = min(max(1, count), chapters.count)
        return (0..<groupCount).map { index in
            let start = index * chapters.count / groupCount
            let end = (index + 1) * chapters.count / groupCount
            return Array(chapters[start..<max(start + 1, end)])
        }
    }

    private static func quoted(in text: String) -> [Passage] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[“「『"]([^”」』"\n]{2,100})[”」』"]"#
        ) else { return [] }
        let nsText = text as NSString
        return regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return Passage(
                text: nsText.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                location: match.range.location
            )
        }
    }

    private static func actionLines(in text: String) -> [String] {
        text.split(separator: "\n").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter {
            (12...110).contains($0.count)
                && !$0.contains("“")
                && !$0.hasPrefix("[")
                && !$0.hasPrefix("【")
        }
    }

    private static func firstAction(in text: String) -> String {
        actionLines(in: text).first ?? String(text.prefix(70))
    }

    private static func segment(_ text: String, index: Int, count: Int) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }
        let start = index * characters.count / count
        let end = min(characters.count, (index + 1) * characters.count / count)
        return String(characters[start..<max(start + 1, end)])
    }

    private static func inferSpeaker(
        source: String,
        position: Int,
        characters: [CharacterProfile]
    ) -> String? {
        let nsText = source as NSString
        let lower = max(0, position - 220)
        let upper = min(nsText.length, position + 220)
        let context = nsText.substring(
            with: NSRange(location: lower, length: max(0, upper - lower))
        )
        return characters
            .filter { context.contains($0.sourceName) }
            .max { lhs, rhs in lhs.occurrences < rhs.occurrences }?
            .targetName
    }

    private static func inferLocation(_ text: String) -> (heading: String, name: String) {
        let options: [(String, String, String)] = [
            ("夜市|地摊", "夜·外", "城市夜市"),
            ("医院|病房|急诊", "日·内", "医院"),
            ("教室|学校|一中", "日·内", "教室"),
            ("家里|客厅|卧室|公寓", "夜·内", "住所"),
            ("商场|店里|超市", "日·内", "商场"),
            ("街|路边|巷", "日·外", "街道"),
        ]
        for (pattern, heading, name) in options
        where text.range(of: pattern, options: .regularExpression) != nil {
            return (heading, name)
        }
        return ("日·外", "城市街区")
    }
}

enum PipelineError: LocalizedError {
    case invalidNames
    case noDocument
    case missingAPIKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidNames: "人物新名不能为空或重复"
        case .noDocument: "请先导入小说文本"
        case .missingAPIKey: "在线模式需要先配置 API Key"
        case .invalidResponse: "模型返回了无法解析的结构化内容"
        }
    }
}
