import Foundation

enum OfflinePipeline {
    static func run(
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions
    ) throws -> AdaptationResult {
        guard !document.chapters.isEmpty else { throw PipelineError.noDocument }
        guard CharacterExtractor.validate(characters) else { throw PipelineError.invalidNames }
        let outputLanguage = options.outputLanguage(for: document)

        let bible = makeStoryBible(
            document: document,
            characters: characters,
            episodeCount: options.episodeCount,
            language: outputLanguage
        )
        var episodes = (0..<options.episodeCount).map { offset in
            makeEpisode(
                number: offset + 1,
                document: document,
                characters: characters,
                options: options,
                previousExit: outputLanguage == .english
                    ? (offset == 0 ? "The story has not begun" : "The previous cliffhanger remains unresolved")
                    : (offset == 0 ? "故事尚未开始" : "上一集卡点尚未解决"),
                language: outputLanguage
            )
        }
        episodes = episodes.map { episode in
            var updated = episode
            updated.runtime = EpisodeBudget.estimateRuntime(
                scenes: episode.scenes,
                language: outputLanguage
            )
            updated.content = render(updated, language: outputLanguage)
            return updated
        }
        let quality = QualityEvaluator.evaluate(
            episodes: episodes,
            characters: characters,
            options: options,
            outputLanguage: outputLanguage
        )
        return AdaptationResult(
            logline: outputLanguage == .english
                ? "\(characters.first?.targetName ?? "The protagonist") returns from ruin and fights through betrayal to reclaim control of their fate."
                : "\(characters.first?.targetName ?? "主人公")从绝境归来，在层层背叛与真相中夺回命运。",
            genre: options.resolvedGenre(for: outputLanguage),
            themes: outputLanguage == .english
                ? ["Return", "Choice", "Truth", "Cost"]
                : ["归来", "选择", "真相", "代价"],
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

    static func render(_ episode: Episode, language: AppLanguage = .chinese) -> String {
        var lines = language == .english
            ? [
                "EPISODE \(episode.number) — \(episode.title)",
                "[EPISODE OBJECTIVE] \(episode.objective)",
                "[COLD OPEN] \(episode.openingHook)",
                "",
            ]
            : [
                "第\(episode.number)集《\(episode.title)》",
                "【本集目标】\(episode.objective)",
                "【冷开场】\(episode.openingHook)",
                "",
            ]
        for (index, scene) in episode.scenes.enumerated() {
            lines.append("\(index + 1). \(scene.heading) \(scene.location)")
            lines.append((language == .english ? "ACTION: " : "△ ") + scene.action)
            for dialogue in scene.dialogue {
                lines.append("\(dialogue.speaker)\(language == .english ? ": " : "：")\(dialogue.text)")
            }
            lines.append("")
        }
        lines.append((language == .english ? "[REVERSAL] " : "【反转】") + episode.reversal)
        lines.append((language == .english ? "[CLIFFHANGER] " : "【卡点】") + episode.endHook)
        if let runtime = episode.runtime {
            lines.append(language == .english
                ? "[ESTIMATED RUNTIME] Approximately \(runtime.estimatedSeconds) seconds"
                : "【表演估时】约 \(runtime.estimatedSeconds) 秒")
        }
        return lines.joined(separator: "\n")
    }

    private static func makeStoryBible(
        document: NovelDocument,
        characters: [CharacterProfile],
        episodeCount: Int,
        language: AppLanguage
    ) -> StoryBible {
        let canonical = characters.map { character in
            CanonicalCharacter(
                id: character.id,
                sourceNames: [character.sourceName],
                scriptName: character.targetName,
                role: language == .english ? englishRole(character.role) : character.role,
                relationships: [language == .english
                    ? "Relationships must be confirmed by source evidence"
                    : "关系须由原文证据确认"],
                evidenceChapterIDs: document.chapters.filter {
                    $0.content.contains(character.sourceName)
                }.prefix(8).map(\.id)
            )
        }
        let timeline = document.chapters.prefix(max(episodeCount, 8)).enumerated().map { index, chapter in
            TimelineEvent(
                id: "timeline-\(index + 1)",
                order: index + 1,
                location: language == .english ? "As established in the source chapter" : "以原文章节为准",
                time: language == .english ? "Chapter \(chapter.index)" : "第\(chapter.index)章",
                participants: characters.filter { chapter.content.contains($0.sourceName) }.map(\.targetName),
                cause: language == .english
                    ? (index == 0 ? "Opening of the story" : "Consequence of the previous chapter")
                    : (index == 0 ? "故事开端" : "承接上一章后果"),
                event: summarySentence(chapter.content),
                effect: language == .english ? "Advances the conflict into its next stage" : "推动下一阶段冲突",
                evidenceChapterIDs: [chapter.id]
            )
        }
        return StoryBible(
            premise: document.intro.isEmpty ? summarySentence(document.rawText) : document.intro,
            canonicalCharacters: canonical,
            worldRules: [
                WorldRule(
                    id: "world-1",
                    subject: language == .english ? "Abilities and identities" : "能力与身份",
                    fact: language == .english
                        ? "All abilities, injuries, identities, and relationships must follow source evidence"
                        : "所有能力、伤势、身份和关系以原文证据为准",
                    cause: language == .english
                        ? "Prevents analytical inference from becoming invented canon"
                        : "避免把推测写成既定事实",
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
        previousExit: String,
        language: AppLanguage
    ) -> Episode {
        let chapterIndex = min(document.chapters.count - 1, (number - 1) * document.chapters.count / max(1, options.episodeCount))
        let nextIndex = min(document.chapters.count - 1, chapterIndex + 1)
        let sourceChapters = Array(document.chapters[chapterIndex...nextIndex])
        let lead = characters.first?.targetName ?? (language == .english ? "Elias" : "程野")
        let ally = characters.dropFirst().first?.targetName ?? (language == .english ? "Mara" : "沈知夏")
        let opponent = characters.dropFirst(2).first?.targetName ?? (language == .english ? "Victor" : "顾川")
        let fact = summarySentence(sourceChapters.map(\.content).joined(separator: "\n"))
        let sourceTitle = sourceChapters.first?.title ?? ""
        let chapterTitle = language == .english && (sourceTitle.isEmpty || sourceTitle == "正文")
            ? "Source Story"
            : (sourceTitle.isEmpty ? "命运反转" : sourceTitle)
        let sceneCount = dynamicSceneCount(number: number, duration: options.durationSeconds, fact: fact)
        let conflict = language == .english
            ? "\(lead) must choose how to respond to the crisis triggered by \"\(chapterTitle)\""
            : "\(lead)必须在“\(chapterTitle)”引发的危机中作出选择"
        let opening = language == .english
            ? "As \(lead) moves, \(opponent) reveals evidence that could change everything."
            : "\(lead)刚要行动，\(opponent)当众亮出一件足以改变局面的证据。"
        let reversal = language == .english
            ? "The evidence aimed at \(lead) exposes a flaw in what \(opponent) has concealed."
            : "看似针对\(lead)的证据，反而暴露了\(opponent)隐瞒的漏洞。"
        let endHook = language == .english
            ? "\(lead) pins down the evidence and says, \"You are not the one who did it.\" Cut to black."
            : "\(lead)按住关键证据，低声说：“真正动手的人，不是你。”画面骤黑。"
        let contract = EpisodeContract(
            dominantConflict: conflict,
            newInformation: [fact],
            visualHook: opening,
            transitionFromPrevious: previousExit,
            activePropThreads: [language == .english ? "Critical evidence" : "关键证据"],
            entryState: language == .english
                ? "\(lead) has limited information as external pressure closes in"
                : "\(lead)掌握的信息有限，外部压力逼近",
            exitState: language == .english
                ? "\(lead) finds a deeper truth and the conflict escalates"
                : "\(lead)发现更深层真相，冲突升级"
        )
        let scenes = makeScenes(
            count: sceneCount,
            number: number,
            lead: lead,
            ally: ally,
            opponent: opponent,
            fact: fact,
            sourceTitle: chapterTitle,
            language: language
        )
        return Episode(
            id: "episode-\(number)",
            number: number,
            title: conciseTitle(chapterTitle, fallback: language == .english ? "Truth Approaches" : "真相逼近"),
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
        sourceTitle: String,
        language: AppLanguage
    ) -> [ScriptScene] {
        if language == .english {
            return makeEnglishScenes(
                count: count,
                number: number,
                lead: lead,
                ally: ally,
                opponent: opponent,
                sourceTitle: sourceTitle
            )
        }
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

    private static func makeEnglishScenes(
        count: Int,
        number: Int,
        lead: String,
        ally: String,
        opponent: String,
        sourceTitle: String
    ) -> [ScriptScene] {
        let first = ScriptScene(
            id: "episode-\(number)-scene-1",
            heading: "INT. COUNCIL CHAMBER - DAY",
            location: "A black piece of evidence rests on the table as footsteps approach outside.",
            action: "\(opponent) pushes the evidence forward. \(lead) studies a hidden mark on the sleeve while \(ally) quietly blocks the exit.",
            dialogue: [
                DialogueLine(speaker: opponent, text: "The evidence is here, and everyone has seen what you did."),
                DialogueLine(speaker: lead, text: "You rushed to accuse me because you feared I would examine it."),
                DialogueLine(speaker: opponent, text: "You have no authority here, and no one believes your story."),
                DialogueLine(speaker: ally, text: "Then let the examination finish, unless there is something you fear."),
                DialogueLine(speaker: opponent, text: "Fine, but when this ends, you both leave without another word."),
                DialogueLine(speaker: lead, text: "This hidden mark could only have been left by the person responsible."),
                DialogueLine(speaker: opponent, text: "That is impossible; the object came directly from \(sourceTitle)."),
            ]
        )
        let second = ScriptScene(
            id: "episode-\(number)-scene-2",
            heading: "INT. SIDE CORRIDOR - CONTINUOUS",
            location: "The corridor lights flicker as a thin crack spreads across the evidence.",
            action: "\(lead) turns back and holds the object under a lamp. Dark smoke escapes through the crack as \(opponent) lunges for it.",
            dialogue: [
                DialogueLine(speaker: ally, text: "The surface is turning black, and the crack is still moving."),
                DialogueLine(speaker: opponent, text: "Put it down now; that object can kill everyone in this corridor."),
                DialogueLine(speaker: lead, text: "You finally admitted that the evidence was never safe or ordinary."),
                DialogueLine(speaker: opponent, text: "I only delivered it, and I was never told what it contained."),
                DialogueLine(speaker: ally, text: "Who gave the order, and why were we chosen as witnesses?"),
                DialogueLine(speaker: lead, text: "The answer is inside this smoke, and someone expected us to miss it."),
                DialogueLine(speaker: opponent, text: "If you keep searching, the people behind this will destroy us all."),
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
                heading: "EXT. STONE STEPS - CONTINUOUS",
                location: "Wind crosses the steps as a distant alarm rings three times.",
                action: "The smoke forms half of an emblem. \(lead) memorizes it and seals the evidence inside a coat.",
                dialogue: [
                    DialogueLine(speaker: ally, text: "Whose emblem is that, and why was half of it erased?"),
                    DialogueLine(speaker: lead, text: "It belongs to someone who was declared dead years ago."),
                    DialogueLine(speaker: opponent, text: "You still do not understand who you have challenged tonight."),
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

    private static func englishRole(_ role: String) -> String {
        return switch role {
        case "核心主角", "主角", "男主", "女主": "Protagonist"
        case "主要角色": "Main character"
        case "关键配角", "配角", "盟友": "Supporting character"
        default: role
        }
    }
}

enum PipelineError: LocalizedError {
    case noDocument
    case invalidNames
    case missingAPIKey
    case noResult
    case noBookAnalysis
    case noStoryboard
    case missingImageModel
    case missingSpeechModel
    case noSpeechText

    var errorDescription: String? {
        switch self {
        case .noDocument: "请先导入故事或剧本"
        case .invalidNames: "人物新名不能为空、重复、与原名相同或使用占位名"
        case .missingAPIKey: "在线模式需要先配置 API Key"
        case .noResult: "尚未生成可导出的剧本"
        case .noBookAnalysis: "尚未生成拆书报告"
        case .noStoryboard: "尚未生成分镜制作包"
        case .missingImageModel: "请先在模型设置中填写图片模型；分镜文本仍可离线使用"
        case .missingSpeechModel: "请先在模型设置中填写语音模型；分镜文本仍可离线使用"
        case .noSpeechText: "当前镜头没有可用于配音的旁白或台词"
        }
    }
}
