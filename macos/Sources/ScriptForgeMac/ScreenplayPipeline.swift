import Foundation

enum ScreenplayPipeline {
    static func characters(from document: NovelDocument, limit: Int = 24) -> [CharacterProfile] {
        var scores: [String: Int] = [:]
        for chapter in document.chapters {
            for line in chapter.content.components(separatedBy: "\n") {
                if let cast = fieldValue(in: line, labels: ["人物", "角色", "CAST"]) {
                    for name in splitCast(cast) {
                        scores[name, default: 0] += 8
                    }
                }
                if let dialogue = parseDialogue(line) {
                    scores[dialogue.speaker, default: 0] += 12
                }
            }
        }

        return scores
            .filter { isUsefulCharacterName($0.key) }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(limit)
            .enumerated()
            .map { offset, entry in
                CharacterProfile(
                    id: "screenplay-character-\(offset + 1)",
                    sourceName: entry.key,
                    targetName: entry.key,
                    role: offset == 0 ? "原稿核心人物" : "原稿人物",
                    traits: ["沿用原稿设定", "保持造型连续"],
                    occurrences: entry.value,
                    locked: true,
                    nameSource: .manual
                )
            }
    }

    static func run(
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions
    ) throws -> AdaptationResult {
        guard document.resolvedSourceKind == .screenplay, !document.chapters.isEmpty else {
            throw PipelineError.noDocument
        }

        var episodes = document.chapters.enumerated().map { offset, chapter in
            makeEpisode(
                chapter: chapter,
                position: offset,
                previous: offset > 0 ? document.chapters[offset - 1].title : "原稿开篇"
            )
        }
        episodes = episodes.map { episode in
            var updated = episode
            updated.runtime = EpisodeBudget.estimateRuntime(scenes: episode.scenes)
            return updated
        }

        var qualityOptions = options
        qualityOptions.episodeCount = episodes.count
        let quality = QualityEvaluator.evaluate(
            episodes: episodes,
            characters: characters,
            options: qualityOptions
        )
        let keywords = document.chapters.flatMap { chapter in
            chapter.content.components(separatedBy: "\n").compactMap {
                fieldValue(in: $0, labels: ["关键词", "主题", "KEYWORDS"])
            }.flatMap(splitList)
        }

        return AdaptationResult(
            logline: document.intro.isEmpty
                ? summarySentence(document.chapters.first?.content ?? document.rawText)
                : document.intro,
            genre: fieldValue(in: document.rawText, labels: ["题材", "类型", "GENRE"])
                ?? options.resolvedGenre(for: AppLanguage.detect(in: document.rawText)),
            themes: Array(Set(keywords)).sorted().prefix(8).map { $0 },
            sourceFacts: document.chapters.prefix(8).map {
                "[\($0.id)] \(summarySentence($0.content))"
            },
            storyBible: makeStoryBible(document: document, characters: characters, episodes: episodes),
            episodes: episodes,
            quality: quality,
            generatedAt: Date(),
            mode: .offline
        )
    }

    private static func makeEpisode(
        chapter: Chapter,
        position: Int,
        previous: String
    ) -> Episode {
        let parsed = parseEpisodeBody(chapter)
        let scenes = parsed.scenes.isEmpty ? [fallbackScene(chapter)] : parsed.scenes
        let opening = firstMeaningfulAction(scenes)
        let endHook = parsed.hook.isEmpty
            ? fallbackHook(chapter.content, scenes: scenes)
            : parsed.hook
        let keywords = parsed.keywords.isEmpty ? "原稿核心冲突" : parsed.keywords.joined(separator: "、")
        let contract = EpisodeContract(
            dominantConflict: keywords,
            newInformation: [summarySentence(chapter.content)],
            visualHook: opening,
            transitionFromPrevious: position == 0 ? "原稿开篇" : "承接《\(previous)》的既定后果",
            activePropThreads: [],
            entryState: "保持原稿本集开场状态",
            exitState: endHook
        )
        var episode = Episode(
            id: "episode-\(chapter.index)-\(position + 1)",
            number: chapter.index,
            title: chapter.title,
            sourceChapterIDs: [chapter.id],
            plannedSceneCount: scenes.count,
            openingHook: opening,
            objective: "保留《\(chapter.title)》的原稿事件、人物关系与冲突",
            reversal: "保持原稿既定反转，不新增事实",
            endHook: endHook,
            contract: contract,
            runtime: nil,
            semanticAudit: nil,
            scenes: scenes,
            content: "第\(chapter.index)集《\(chapter.title)》\n\(chapter.content)"
        )
        episode.runtime = EpisodeBudget.estimateRuntime(scenes: scenes)
        return episode
    }

    private static func parseEpisodeBody(_ chapter: Chapter) -> ParsedEpisodeBody {
        enum BlockMode { case neutral, action, dialogue, narration }

        var mode = BlockMode.neutral
        var builders: [SceneBuilder] = []
        var current: SceneBuilder?
        var hook = ""
        var keywords: [String] = []

        func ensureScene() -> SceneBuilder {
            current ?? SceneBuilder(heading: "场次 \(builders.count + 1)")
        }
        func flushScene() {
            guard let value = current, value.hasContent else {
                current = nil
                return
            }
            builders.append(value)
            current = nil
        }

        for rawLine in chapter.content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let value = fieldValue(in: line, labels: ["关键词", "主题", "KEYWORDS"]) {
                keywords += splitList(value)
                continue
            }
            if fieldValue(in: line, labels: ["位置", "情绪", "情绪强度", "人物", "角色", "CAST"]) != nil {
                continue
            }
            if SourceStructureDetector.isSceneHeading(line) {
                flushScene()
                current = SceneBuilder(heading: line)
                mode = .neutral
                continue
            }
            if let marker = parseBlockMarker(line) {
                switch marker.label {
                case "钩子", "卡点", "HOOK":
                    if !marker.value.isEmpty { hook = marker.value }
                    mode = .neutral
                case "对白", "台词", "DIALOGUE":
                    mode = .dialogue
                    if let dialogue = parseDialogue(marker.value) {
                        var scene = ensureScene()
                        scene.dialogue.append(dialogue)
                        current = scene
                    }
                case "旁白", "NARRATION":
                    mode = .narration
                    if !marker.value.isEmpty {
                        var scene = ensureScene()
                        scene.actionLines.append("旁白：" + marker.value)
                        current = scene
                    }
                default:
                    mode = .action
                    if !marker.value.isEmpty {
                        var scene = ensureScene()
                        scene.actionLines.append(cleanAction(marker.value))
                        current = scene
                    }
                }
                continue
            }
            if mode == .dialogue, let dialogue = parseDialogue(line) {
                var scene = ensureScene()
                scene.dialogue.append(dialogue)
                current = scene
                continue
            }
            if let dialogue = parseDialogue(line) {
                var scene = ensureScene()
                scene.dialogue.append(dialogue)
                current = scene
                continue
            }
            if mode == .dialogue, var scene = current, !scene.dialogue.isEmpty {
                let last = scene.dialogue.removeLast()
                scene.dialogue.append(DialogueLine(
                    speaker: last.speaker,
                    text: last.text + " " + line
                ))
                current = scene
                continue
            }
            var scene = ensureScene()
            scene.actionLines.append(mode == .narration ? "旁白：" + line : cleanAction(line))
            current = scene
        }
        flushScene()

        return ParsedEpisodeBody(
            scenes: builders.enumerated().map { offset, builder in
                builder.build(episodeNumber: chapter.index, sceneNumber: offset + 1)
            },
            hook: hook,
            keywords: Array(Set(keywords)).sorted()
        )
    }

    private static func fallbackScene(_ chapter: Chapter) -> ScriptScene {
        ScriptScene(
            id: "episode-\(chapter.index)-scene-1",
            heading: "场次 1",
            location: "按原稿场景",
            action: chapter.content.trimmingCharacters(in: .whitespacesAndNewlines),
            dialogue: []
        )
    }

    private static func makeStoryBible(
        document: NovelDocument,
        characters: [CharacterProfile],
        episodes: [Episode]
    ) -> StoryBible {
        StoryBible(
            premise: document.intro.isEmpty ? summarySentence(document.rawText) : document.intro,
            canonicalCharacters: characters.map { character in
                CanonicalCharacter(
                    id: character.id,
                    sourceNames: [character.sourceName],
                    scriptName: character.targetName,
                    role: character.role,
                    relationships: ["沿用原稿关系"],
                    evidenceChapterIDs: document.chapters.filter {
                        $0.content.contains(character.sourceName)
                    }.map(\.id)
                )
            },
            worldRules: [
                WorldRule(
                    id: "screenplay-source-rule",
                    subject: "已有剧本",
                    fact: "人物、事件、设定、对白与结局以导入原稿为准",
                    cause: "剧本直通模式不得擅自二次改编",
                    evidenceChapterIDs: document.chapters.map(\.id)
                ),
            ],
            propThreads: [],
            timeline: episodes.enumerated().map { offset, episode in
                TimelineEvent(
                    id: "screenplay-timeline-\(offset + 1)",
                    order: offset + 1,
                    location: episode.scenes.first?.location ?? "按原稿场景",
                    time: "第\(episode.number)集",
                    participants: Array(Set(episode.scenes.flatMap(\.dialogue).map(\.speaker))).sorted(),
                    cause: offset == 0 ? "原稿开篇" : "承接上一集",
                    event: summarySentence(episode.content),
                    effect: episode.endHook,
                    evidenceChapterIDs: episode.sourceChapterIDs
                )
            }
        )
    }

    private static func fieldValue(in line: String, labels: [String]) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = #"(?i)^"# + escaped + #"\s*[:：]\s*(.+)$"#
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                let matched = String(trimmed[range])
                if let separator = matched.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                    return String(matched[matched.index(after: separator)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private static func parseBlockMarker(_ line: String) -> (label: String, value: String)? {
        let pattern = #"^[\[【（(]?\s*(画面|动作|对白|台词|旁白|钩子|卡点|镜头|ACTION|VISUAL|DIALOGUE|NARRATION|HOOK|SHOT)\s*[\]】）)]?\s*[:：]?\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
              ),
              let labelRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line) else { return nil }
        return (
            String(line[labelRange]).uppercased(),
            String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseDialogue(_ line: String) -> DialogueLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SourceStructureDetector.isDialogueLine(trimmed),
              let separator = trimmed.firstIndex(where: { $0 == "：" || $0 == ":" }) else {
            return nil
        }
        var speaker = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
        speaker = speaker.replacingOccurrences(
            of: #"\s*[（(][^）)]{1,16}[）)]\s*$"#,
            with: "",
            options: .regularExpression
        )
        let text = String(trimmed[trimmed.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        guard !speaker.isEmpty, !text.isEmpty else { return nil }
        return DialogueLine(speaker: speaker, text: text)
    }

    private static func splitCast(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: "、，,;/；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isUsefulCharacterName)
    }

    private static func splitList(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: "、，,;/；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isUsefulCharacterName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = ["人物", "角色", "众人", "人群", "全体", "画外音", "旁白"]
        return (1...24).contains(trimmed.count) && !invalid.contains(trimmed)
    }

    private static func cleanAction(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^[△▽▼▲•·]+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMeaningfulAction(_ scenes: [ScriptScene]) -> String {
        scenes.first(where: { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty })?.action
            .prefix(100).description ?? "按原稿画面开场"
    }

    private static func fallbackHook(_ content: String, scenes: [ScriptScene]) -> String {
        if let dialogue = scenes.last?.dialogue.last {
            return dialogue.speaker + "：" + dialogue.text
        }
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.last.map { String($0.prefix(120)) } ?? "保持原稿结尾"
    }

    private static func summarySentence(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "原稿在本段推进人物关系与核心冲突。" }
        let end = compact.firstIndex(where: { "。！？!?".contains($0) }) ?? compact.endIndex
        return String(compact[..<end].prefix(140))
    }
}

private struct ParsedEpisodeBody {
    let scenes: [ScriptScene]
    let hook: String
    let keywords: [String]
}

private struct SceneBuilder {
    let heading: String
    var actionLines: [String] = []
    var dialogue: [DialogueLine] = []

    var hasContent: Bool { !actionLines.isEmpty || !dialogue.isEmpty }

    func build(episodeNumber: Int, sceneNumber: Int) -> ScriptScene {
        let action = actionLines.filter { !$0.isEmpty }.joined(separator: "\n")
        let location = inferLocation(action: action)
        return ScriptScene(
            id: "episode-\(episodeNumber)-scene-\(sceneNumber)",
            heading: heading,
            location: location,
            action: action.isEmpty ? "按原稿对白完成本场表演。" : action,
            dialogue: dialogue
        )
    }

    private func inferLocation(action: String) -> String {
        let descriptiveHeading = heading.replacingOccurrences(
            of: #"^(?:场次|场景|SCENE)\s*[0-9一二三四五六七八九十百千零两〇]+\s*[:：.]?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !descriptiveHeading.isEmpty { return String(descriptiveHeading.prefix(80)) }
        let first = action.components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? "按原稿场景" : String(first.prefix(80))
    }
}
