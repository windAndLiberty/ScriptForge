import Foundation

enum OfflinePipeline {
    static func run(
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions
    ) throws -> AdaptationResult {
        guard !document.chapters.isEmpty else { throw PipelineError.noDocument }
        guard CharacterExtractor.validate(characters) else { throw PipelineError.invalidNames }

        let bible = makeStoryBible(document: document, characters: characters, episodeCount: options.episodeCount)
        var episodes = (0..<options.episodeCount).map { offset in
            makeEpisode(
                number: offset + 1,
                document: document,
                characters: characters,
                options: options,
                previousExit: offset == 0 ? "故事尚未开始" : "上一集卡点尚未解决"
            )
        }
        episodes = episodes.map { episode in
            var updated = episode
            updated.runtime = EpisodeBudget.estimateRuntime(scenes: episode.scenes)
            updated.content = render(updated)
            return updated
        }
        let quality = QualityEvaluator.evaluate(
            episodes: episodes,
            characters: characters,
            options: options
        )
        return AdaptationResult(
            logline: "\(characters.first?.targetName ?? "主人公")从绝境归来，在层层背叛与真相中夺回命运。",
            genre: options.genre,
            themes: ["归来", "选择", "真相", "代价"],
            sourceFacts: document.chapters.prefix(8).map {
                "[\($0.id)] \(summarySentence($0.content))"
            },
            storyBible: bible,
            episodes: episodes,
            quality: quality,
            generatedAt: Date(),
            mode: .offline
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
            for dialogue in scene.dialogue {
                lines.append("\(dialogue.speaker)：\(dialogue.text)")
            }
            lines.append("")
        }
        lines.append("【反转】\(episode.reversal)")
        lines.append("【卡点】\(episode.endHook)")
        if let runtime = episode.runtime {
            lines.append("【表演估时】约 \(runtime.estimatedSeconds) 秒")
        }
        return lines.joined(separator: "\n")
    }

    private static func makeStoryBible(
        document: NovelDocument,
        characters: [CharacterProfile],
        episodeCount: Int
    ) -> StoryBible {
        let canonical = characters.map { character in
            CanonicalCharacter(
                id: character.id,
                sourceNames: [character.sourceName],
                scriptName: character.targetName,
                role: character.role,
                relationships: ["关系须由原文证据确认"],
                evidenceChapterIDs: document.chapters.filter {
                    $0.content.contains(character.sourceName)
                }.prefix(8).map(\.id)
            )
        }
        let timeline = document.chapters.prefix(max(episodeCount, 8)).enumerated().map { index, chapter in
            TimelineEvent(
                id: "timeline-\(index + 1)",
                order: index + 1,
                location: "以原文章节为准",
                time: "第\(chapter.index)章",
                participants: characters.filter { chapter.content.contains($0.sourceName) }.map(\.targetName),
                cause: index == 0 ? "故事开端" : "承接上一章后果",
                event: summarySentence(chapter.content),
                effect: "推动下一阶段冲突",
                evidenceChapterIDs: [chapter.id]
            )
        }
        return StoryBible(
            premise: document.intro.isEmpty ? summarySentence(document.rawText) : document.intro,
            canonicalCharacters: canonical,
            worldRules: [
                WorldRule(
                    id: "world-1",
                    subject: "能力与身份",
                    fact: "所有能力、伤势、身份和关系以原文证据为准",
                    cause: "避免把推测写成既定事实",
                    evidenceChapterIDs: document.chapters.prefix(3).map(\.id)
                ),
            ],
            propThreads: [],
            timeline: timeline
        )
    }

    private static func makeEpisode(
        number: Int,
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions,
        previousExit: String
    ) -> Episode {
        let chapterIndex = min(document.chapters.count - 1, (number - 1) * document.chapters.count / max(1, options.episodeCount))
        let nextIndex = min(document.chapters.count - 1, chapterIndex + 1)
        let sourceChapters = Array(document.chapters[chapterIndex...nextIndex])
        let lead = characters.first?.targetName ?? "程野"
        let ally = characters.dropFirst().first?.targetName ?? "沈知夏"
        let opponent = characters.dropFirst(2).first?.targetName ?? "顾川"
        let fact = summarySentence(sourceChapters.map(\.content).joined(separator: "\n"))
        let chapterTitle = sourceChapters.first?.title ?? "命运反转"
        let sceneCount = dynamicSceneCount(number: number, duration: options.durationSeconds, fact: fact)
        let conflict = "\(lead)必须在“\(chapterTitle)”引发的危机中作出选择"
        let opening = "\(lead)刚要行动，\(opponent)当众亮出一件足以改变局面的证据。"
        let reversal = "看似针对\(lead)的证据，反而暴露了\(opponent)隐瞒的漏洞。"
        let endHook = "\(lead)按住关键证据，低声说：“真正动手的人，不是你。”画面骤黑。"
        let contract = EpisodeContract(
            dominantConflict: conflict,
            newInformation: [fact],
            visualHook: opening,
            transitionFromPrevious: previousExit,
            activePropThreads: ["关键证据"],
            entryState: "\(lead)掌握的信息有限，外部压力逼近",
            exitState: "\(lead)发现更深层真相，冲突升级"
        )
        let scenes = makeScenes(
            count: sceneCount,
            number: number,
            lead: lead,
            ally: ally,
            opponent: opponent,
            fact: fact,
            sourceTitle: chapterTitle
        )
        return Episode(
            id: "episode-\(number)",
            number: number,
            title: conciseTitle(chapterTitle, fallback: "真相逼近"),
            sourceChapterIDs: sourceChapters.map(\.id),
            plannedSceneCount: sceneCount,
            openingHook: opening,
            objective: conflict,
            reversal: reversal,
            endHook: endHook,
            contract: contract,
            runtime: nil,
            semanticAudit: nil,
            scenes: scenes,
            content: ""
        )
    }

    private static func makeScenes(
        count: Int,
        number: Int,
        lead: String,
        ally: String,
        opponent: String,
        fact: String,
        sourceTitle: String
    ) -> [ScriptScene] {
        let first = ScriptScene(
            id: "episode-\(number)-scene-1",
            heading: "内景 议事厅 - 日",
            location: "众人围住桌上的黑色证物，门外脚步声逼近。",
            action: "△ \(opponent)把证物推到桌边。\(lead)没有伸手，先盯住对方袖口的暗纹；\(ally)悄悄挡住出口。",
            dialogue: [
                DialogueLine(speaker: opponent, text: "证据在这，你还想狡辩？"),
                DialogueLine(speaker: lead, text: "急着定罪，说明你怕我看。"),
                DialogueLine(speaker: opponent, text: "一个废人，也配查我？"),
                DialogueLine(speaker: ally, text: "让他看完，你怕什么？"),
                DialogueLine(speaker: opponent, text: "好。看完就滚出去。"),
                DialogueLine(speaker: lead, text: "这道暗纹，只有凶手会留。"),
                DialogueLine(speaker: opponent, text: "你胡说！这分明来自“\(sourceTitle)”！"),
            ]
        )
        let second = ScriptScene(
            id: "episode-\(number)-scene-2",
            heading: "内景 侧廊 - 连续",
            location: "长廊灯火忽明忽暗，证物表面浮出一道细裂。",
            action: "△ \(lead)突然折返，把证物按在灯下。黑气沿着裂纹窜出；\(opponent)脸色骤变，伸手便抢。",
            dialogue: [
                DialogueLine(speaker: ally, text: "它在变黑！"),
                DialogueLine(speaker: opponent, text: "放手！那东西会要你的命！"),
                DialogueLine(speaker: lead, text: "你终于承认它有问题。"),
                DialogueLine(speaker: opponent, text: "我只是奉命送来。"),
                DialogueLine(speaker: ally, text: "奉谁的命？"),
                DialogueLine(speaker: lead, text: "答案就在这缕气里。"),
                DialogueLine(speaker: opponent, text: "你查下去，所有人都会死。"),
            ]
        )
        if count == 1 {
            return [ScriptScene(
                id: first.id,
                heading: first.heading,
                location: first.location,
                action: first.action + " " + second.action,
                dialogue: first.dialogue + second.dialogue
            )]
        }
        if count == 3 {
            let third = ScriptScene(
                id: "episode-\(number)-scene-3",
                heading: "外景 石阶 - 连续",
                location: "夜风卷过石阶，远处警钟突然连响三声。",
                action: "△ 黑气在空中凝成半枚印记。\(lead)抬眼记下纹路，反手把证物封进袖中。",
                dialogue: [
                    DialogueLine(speaker: ally, text: "这印记属于谁？"),
                    DialogueLine(speaker: lead, text: "一个本该死去的人。"),
                    DialogueLine(speaker: opponent, text: "你根本不知道自己惹了谁。"),
                ]
            )
            return [first, second, third]
        }
        return [first, second]
    }

    private static func dynamicSceneCount(number: Int, duration: Int, fact: String) -> Int {
        let range = EpisodeBudget.sceneRange(durationSeconds: duration)
        if fact.count < 80 { return range.lowerBound }
        if number % 4 == 0, range.upperBound >= 3 { return 3 }
        return min(2, range.upperBound)
    }

    private static func conciseTitle(_ value: String, fallback: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(8))
    }

    private static func summarySentence(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "原文在本段推进了人物关系和核心冲突。" }
        let end = compact.firstIndex(where: { "。！？!?".contains($0) }) ?? compact.endIndex
        let sentence = String(compact[..<end])
        return String(sentence.prefix(120))
    }
}

enum PipelineError: LocalizedError {
    case noDocument
    case invalidNames
    case missingAPIKey
    case noResult
    case noBookAnalysis

    var errorDescription: String? {
        switch self {
        case .noDocument: "请先导入小说文本"
        case .invalidNames: "人物新名不能为空、重复、与原名相同或使用占位名"
        case .missingAPIKey: "在线模式需要先配置 API Key"
        case .noResult: "尚未生成可导出的剧本"
        case .noBookAnalysis: "尚未生成拆书报告"
        }
    }
}
