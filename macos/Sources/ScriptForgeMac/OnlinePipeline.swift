import Foundation

enum OnlinePipeline {
    private struct ChunkAnalysis: Codable, Sendable {
        let summary: String
        let facts: [String]
        let keyEvents: [String]
        let emotionalBeats: [String]
        let productionNotes: [String]
        let evidenceChapterIDs: [String]
    }

    private struct StoryBibleResponse: Codable, Sendable {
        let premise: String
        let canonicalCharacters: [CanonicalCharacter]
        let worldRules: [WorldRule]
        let propThreads: [PropThread]
        let timeline: [TimelineEvent]
    }

    private struct EpisodePlan: Codable, Sendable {
        let number: Int
        let title: String
        let sourceChapterIDs: [String]
        let plannedSceneCount: Int
        let openingHook: String
        let objective: String
        let reversal: String
        let endHook: String
        let contract: EpisodeContract
    }

    private struct OutlineResponse: Codable, Sendable {
        let logline: String
        let genre: String
        let themes: [String]
        let sourceFacts: [String]
        let episodes: [EpisodePlan]
    }

    private struct DraftScene: Codable, Sendable {
        let heading: String
        let location: String
        let action: String
        let dialogue: [DraftDialogue]
    }

    private struct DraftDialogue: Codable, Sendable {
        let speaker: String
        let text: String
    }

    private struct EpisodeDraft: Codable, Sendable {
        let scenes: [DraftScene]
    }

    private struct SemanticAuditResponse: Codable, Sendable {
        let score: Int
        let passed: Bool
        let issues: [String]
    }

    private struct SeriesIssueDTO: Codable, Sendable {
        let severity: String
        let category: String
        let episodeNumbers: [Int]
        let evidence: String
        let repairInstruction: String
    }

    private struct SeriesAuditResponse: Codable, Sendable {
        let issues: [SeriesIssueDTO]
    }

    private struct NamingResponse: Codable, Sendable {
        let renames: [CharacterExtractor.RenameProposal]
    }

    static func generateCharacterNames(
        document: NovelDocument,
        characters: [CharacterProfile],
        prompts: [PromptAsset],
        settings: ModelSettings,
        apiKey: String
    ) async throws -> [CharacterProfile] {
        guard !characters.isEmpty else { return [] }
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let response: NamingResponse = try await client.structured(
            stage: .characterNaming,
            instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(["character-naming"], assets: prompts),
            input: """
            为以下人物一次性生成剧本新名。保留 sourceName 原样：
            \(characters.map { "- \($0.sourceName)：\($0.role)，出现 \($0.occurrences) 次，特征 \($0.traits.joined(separator: "、"))" }.joined(separator: "\n"))
            小说类型提示：\(document.title)；\(document.intro.prefix(500))
            """,
            name: "character_renames",
            schema: namingSchema
        )
        return CharacterExtractor.resolveModelNames(characters: characters, proposals: response.renames)
    }

    static func run(
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions,
        prompts: [PromptAsset],
        settings: ModelSettings,
        apiKey: String,
        progress: @escaping (PipelinePhase, String, Double) -> Void
    ) async throws -> AdaptationResult {
        guard CharacterExtractor.validate(characters) else { throw PipelineError.invalidNames }
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let evidenceInstruction = systemBase + "\n\n" + PromptAssets.mergedInstruction(
            ["story-evidence"],
            assets: prompts
        )
        let evidenceFragments = NovelParser.evidenceFragments(chapters: document.chapters)
        let chapterGroups = stride(from: 0, to: evidenceFragments.count, by: 2).map {
            Array(evidenceFragments[$0..<min($0 + 2, evidenceFragments.count)])
        }
        var analyses: [ChunkAnalysis] = []
        for (index, group) in chapterGroups.enumerated() {
            try Task.checkCancellation()
            progress(
                .analysis,
                "正在抽取章节证据 \(index + 1) / \(chapterGroups.count)",
                0.08 + Double(index) / Double(max(1, chapterGroups.count)) * 0.2
            )
            let input = group.map { "[\($0.id)] \($0.title)\n\($0.content)" }.joined(separator: "\n\n")
            let analysis: ChunkAnalysis = try await client.structured(
                stage: .chapterAnalysis,
                instructions: evidenceInstruction,
                input: input,
                name: "chapter_evidence_\(index + 1)",
                schema: chunkSchema
            )
            analyses.append(sanitize(analysis, allowedChapterIDs: Set(group.map(\.id))))
        }

        progress(.bible, "正在建立人物、世界规则与时间线", 0.31)
        let bibleResponse: StoryBibleResponse = try await client.structured(
            stage: .storyBible,
            instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(
                ["story-bible"],
                assets: prompts
            ) + "\n\n剧本只能使用锁定新名：\(characters.map(\.targetName).joined(separator: "、"))。",
            input: """
            【人物映射】
            \(characters.map { "\($0.sourceName) → \($0.targetName)（\($0.role)）" }.joined(separator: "\n"))

            【章节证据】
            \(json(analyses))
            """,
            name: "story_bible",
            schema: storyBibleSchema
        )
        let bible = sanitizeBible(
            StoryBible(
                premise: bibleResponse.premise,
                canonicalCharacters: bibleResponse.canonicalCharacters,
                worldRules: bibleResponse.worldRules,
                propThreads: bibleResponse.propThreads,
                timeline: bibleResponse.timeline
            ),
            document: document,
            characters: characters
        )

        progress(.outline, "正在规划全剧分集契约与动态场次", 0.4)
        let outline: OutlineResponse = try await client.structured(
            stage: .episodeOutline,
            instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(
                ["episode-planning"],
                assets: prompts
            ) + """

            必须规划恰好 \(options.episodeCount) 集；每集时长 \(options.durationSeconds) 秒。
            场次数由剧情决定，允许范围 \(EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds).lowerBound)–\(EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds).upperBound) 场。
            """,
            input: """
            【故事圣经】\(json(bible))
            【章节证据】\(json(analyses))
            【类型】\(options.genre)
            【基调】\(options.tone)
            【趋势策略】\(options.trendPreset.rawValue)
            """,
            name: "episode_outline",
            schema: outlineSchema(episodeCount: options.episodeCount, durationSeconds: options.durationSeconds)
        )
        let plans = normalizePlans(outline.episodes, document: document, options: options)

        var episodes: [Episode] = []
        var repairAttempts = 0
        var acceptedRepairs = 0
        for (index, plan) in plans.enumerated() {
            try Task.checkCancellation()
            progress(
                .drafting,
                "正在生成第 \(index + 1) / \(plans.count) 集",
                0.48 + Double(index) / Double(max(1, plans.count)) * 0.31
            )
            let source = sourceText(for: plan, document: document)
            let previous = episodes.last.map {
                "上一集退出状态：\($0.contract.exitState)\n上一集卡点：\($0.endHook)"
            } ?? "首集：前5秒直接建立视觉冲突"
            let draft: EpisodeDraft = try await client.structured(
                stage: .episodeDraft,
                instructions: draftInstruction(
                    options: options,
                    characters: characters,
                    prompts: prompts,
                    plannedSceneCount: plan.plannedSceneCount
                ),
                input: """
                【故事圣经】\(json(bible))
                【本集契约】\(json(plan))
                【连续性】\(previous)
                【对应原文】\(source)
                """,
                name: "episode_\(plan.number)",
                schema: episodeSchema(durationSeconds: options.durationSeconds)
            )
            var episode = makeEpisode(plan: plan, draft: draft, characters: characters)
            let completeness = EpisodeBudget.assess(scenes: episode.scenes, durationSeconds: options.durationSeconds)
            let semantic = try await semanticAudit(
                episode: episode,
                bible: bible,
                plan: plan,
                prompts: prompts,
                client: client
            )
            episode.runtime = completeness.runtime
            episode.semanticAudit = semantic

            if !completeness.passed || !semantic.passed {
                repairAttempts += 1
                let repaired = try await repairEpisode(
                    episode: episode,
                    issues: completeness.issues + semantic.issues,
                    plan: plan,
                    bible: bible,
                    source: source,
                    options: options,
                    characters: characters,
                    prompts: prompts,
                    client: client
                )
                let repairedCompleteness = EpisodeBudget.assess(
                    scenes: repaired.scenes,
                    durationSeconds: options.durationSeconds
                )
                let repairedSemantic = try await semanticAudit(
                    episode: repaired,
                    bible: bible,
                    plan: plan,
                    prompts: prompts,
                    client: client
                )
                if repairedCompleteness.score >= completeness.score && repairedSemantic.passed {
                    var accepted = repaired
                    accepted.runtime = repairedCompleteness.runtime
                    accepted.semanticAudit = repairedSemantic
                    accepted.content = OfflinePipeline.render(accepted)
                    episode = accepted
                    acceptedRepairs += 1
                }
            }
            episode.content = OfflinePipeline.render(episode)
            episodes.append(episode)
        }

        progress(.quality, "正在执行跨集重叠窗口终审", 0.82)
        let initialAudit = try await auditSeries(
            episodes: episodes,
            bible: bible,
            prompts: prompts,
            client: client
        )
        let targets = Array(Set(initialAudit.issues
            .filter { $0.severity == "blocker" || $0.severity == "major" }
            .flatMap(\.episodeNumbers)))
            .sorted()
            .prefix(8)
        if !targets.isEmpty {
            for episodeNumber in targets {
                guard let index = episodes.firstIndex(where: { $0.number == episodeNumber }) else { continue }
                let related = initialAudit.issues.filter { $0.episodeNumbers.contains(episodeNumber) }
                guard let plan = plans.first(where: { $0.number == episodeNumber }) else { continue }
                repairAttempts += 1
                let repaired = try await repairEpisode(
                    episode: episodes[index],
                    issues: related.map { "\($0.evidence)：\($0.repairInstruction)" },
                    plan: plan,
                    bible: bible,
                    source: sourceText(for: plan, document: document),
                    options: options,
                    characters: characters,
                    prompts: prompts,
                    client: client
                )
                let oldScore = EpisodeBudget.assess(
                    scenes: episodes[index].scenes,
                    durationSeconds: options.durationSeconds
                ).score
                let newAssessment = EpisodeBudget.assess(
                    scenes: repaired.scenes,
                    durationSeconds: options.durationSeconds
                )
                let verification = try await semanticAudit(
                    episode: repaired,
                    bible: bible,
                    plan: plan,
                    prompts: prompts,
                    client: client
                )
                if newAssessment.score >= oldScore && verification.passed {
                    var accepted = repaired
                    accepted.runtime = newAssessment.runtime
                    accepted.semanticAudit = verification
                    accepted.content = OfflinePipeline.render(accepted)
                    episodes[index] = accepted
                    acceptedRepairs += 1
                }
            }
        }

        progress(.quality, "正在复验修订后的全剧连续性", 0.93)
        let finalAudit = try await auditSeries(
            episodes: episodes,
            bible: bible,
            prompts: prompts,
            client: client
        )
        let qualityIssues = finalAudit.issues.map(makeQualityIssue)
        let auditedWindows = seriesWindows(episodes).count
        let quality = QualityEvaluator.evaluate(
            episodes: episodes,
            characters: characters,
            options: options,
            semanticIssues: qualityIssues,
            repairAttempts: repairAttempts,
            acceptedRepairs: acceptedRepairs,
            auditedWindows: auditedWindows
        )
        return AdaptationResult(
            logline: renamed(outline.logline, characters),
            genre: outline.genre,
            themes: outline.themes,
            sourceFacts: outline.sourceFacts.map { renamed($0, characters) },
            storyBible: bible,
            episodes: episodes,
            quality: quality,
            generatedAt: Date(),
            mode: .online
        )
    }

    private static func semanticAudit(
        episode: Episode,
        bible: StoryBible,
        plan: EpisodePlan,
        prompts: [PromptAsset],
        client: LLMClient
    ) async throws -> EpisodeSemanticAudit {
        let response: SemanticAuditResponse = try await client.structured(
            stage: .episodeSemanticAudit,
            instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(["quality-gate"], assets: prompts),
            input: """
            【故事圣经】\(json(bible))
            【本集契约】\(json(plan))
            【候选成稿】\(episode.content.isEmpty ? OfflinePipeline.render(episode) : episode.content)
            只检查本集是否忠于证据、人物动机是否成立、冲突是否真正推进、钩子是否可见可拍。
            """,
            name: "episode_semantic_audit_\(episode.number)",
            schema: semanticAuditSchema
        )
        return EpisodeSemanticAudit(
            score: min(100, max(0, response.score)),
            passed: response.passed && response.score >= 78,
            issues: response.issues
        )
    }

    private static func repairEpisode(
        episode: Episode,
        issues: [String],
        plan: EpisodePlan,
        bible: StoryBible,
        source: String,
        options: AdaptationOptions,
        characters: [CharacterProfile],
        prompts: [PromptAsset],
        client: LLMClient
    ) async throws -> Episode {
        let draft: EpisodeDraft = try await client.structured(
            stage: .episodeRepair,
            instructions: draftInstruction(
                options: options,
                characters: characters,
                prompts: prompts,
                plannedSceneCount: plan.plannedSceneCount
            ) + "\n\n只修复列出的重大问题，保留无问题的冲突、事实和有效台词。",
            input: """
            【故事圣经】\(json(bible))
            【本集契约】\(json(plan))
            【原文证据】\(source)
            【当前成稿】\(episode.content.isEmpty ? OfflinePipeline.render(episode) : episode.content)
            【必须修复】\(issues.joined(separator: "\n- "))
            """,
            name: "episode_repair_\(episode.number)",
            schema: episodeSchema(durationSeconds: options.durationSeconds)
        )
        return makeEpisode(plan: plan, draft: draft, characters: characters)
    }

    private static func auditSeries(
        episodes: [Episode],
        bible: StoryBible,
        prompts: [PromptAsset],
        client: LLMClient
    ) async throws -> SeriesAuditResponse {
        var issues: [SeriesIssueDTO] = []
        for window in seriesWindows(episodes) {
            let response: SeriesAuditResponse = try await client.structured(
                stage: .seriesQualityAudit,
                instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(["quality-gate"], assets: prompts) + """

                只报告可定位的 blocker、major 或 minor。重点检查跨集转场原因、人物关系与名字、能力规则、核心冲突是否重复、伏笔是否无故消失。
                """,
                input: "【故事圣经】\(json(bible))\n【连续分集】\n\(window.map(\.content).joined(separator: "\n\n"))",
                name: "series_audit_\(window.first?.number ?? 1)",
                schema: seriesAuditSchema
            )
            issues.append(contentsOf: response.issues)
        }
        var seen = Set<String>()
        return SeriesAuditResponse(issues: issues.filter {
            seen.insert("\($0.category)|\($0.episodeNumbers)|\($0.evidence)").inserted
        })
    }

    private static func seriesWindows(_ episodes: [Episode]) -> [[Episode]] {
        guard !episodes.isEmpty else { return [] }
        var windows: [[Episode]] = []
        var start = 0
        while start < episodes.count {
            windows.append(Array(episodes[start..<min(start + 4, episodes.count)]))
            if start + 4 >= episodes.count { break }
            start += 3
        }
        return windows
    }

    private static func draftInstruction(
        options: AdaptationOptions,
        characters: [CharacterProfile],
        prompts: [PromptAsset],
        plannedSceneCount: Int
    ) -> String {
        let budget = EpisodeBudget.budget(durationSeconds: options.durationSeconds)
        return systemBase + "\n\n" + PromptAssets.mergedInstruction(["episode-drafting"], assets: prompts) + """

        只能使用以下锁定人物新名：\(characters.map(\.targetName).joined(separator: "、"))。
        本集约 \(options.durationSeconds) 秒，场次数由剧情决定，允许 \(budget.sceneRange.lowerBound)–\(budget.sceneRange.upperBound) 场；分集规划建议 \(plannedSceneCount) 场，但不要为凑数拆场。
        整集目标约 \(budget.dialogueLines.lowerBound)–\(budget.dialogueLines.upperBound) 句短对白、\(budget.spokenCharacters.lowerBound)–\(budget.spokenCharacters.upperBound) 个对白有效字。限制是整集预算，不是每场最少句数。
        每个场次必须有场景时空、地点、可拍动作和对白数组。不得输出旧名。
        """
    }

    private static func makeEpisode(
        plan: EpisodePlan,
        draft: EpisodeDraft,
        characters: [CharacterProfile]
    ) -> Episode {
        let scenes = draft.scenes.enumerated().map { index, scene in
            ScriptScene(
                id: "episode-\(plan.number)-scene-\(index + 1)",
                heading: renamed(scene.heading, characters),
                location: renamed(scene.location, characters),
                action: renamed(scene.action, characters),
                dialogue: scene.dialogue.map {
                    DialogueLine(
                        speaker: renamed($0.speaker, characters),
                        text: renamed($0.text, characters)
                    )
                }
            )
        }
        var episode = Episode(
            id: "episode-\(plan.number)",
            number: plan.number,
            title: renamed(plan.title, characters),
            sourceChapterIDs: plan.sourceChapterIDs,
            plannedSceneCount: plan.plannedSceneCount,
            openingHook: renamed(plan.openingHook, characters),
            objective: renamed(plan.objective, characters),
            reversal: renamed(plan.reversal, characters),
            endHook: renamed(plan.endHook, characters),
            contract: plan.contract,
            runtime: nil,
            semanticAudit: nil,
            scenes: scenes,
            content: ""
        )
        episode.runtime = EpisodeBudget.estimateRuntime(scenes: scenes)
        episode.content = OfflinePipeline.render(episode)
        return episode
    }

    private static func normalizePlans(
        _ source: [EpisodePlan],
        document: NovelDocument,
        options: AdaptationOptions
    ) -> [EpisodePlan] {
        let range = EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds)
        return (0..<options.episodeCount).map { index in
            if source.indices.contains(index) {
                let value = source[index]
                let IDs = value.sourceChapterIDs.filter { id in document.chapters.contains(where: { $0.id == id }) }
                return EpisodePlan(
                    number: index + 1,
                    title: value.title,
                    sourceChapterIDs: IDs.isEmpty ? [document.chapters[min(index, document.chapters.count - 1)].id] : IDs,
                    plannedSceneCount: min(range.upperBound, max(range.lowerBound, value.plannedSceneCount)),
                    openingHook: value.openingHook,
                    objective: value.objective,
                    reversal: value.reversal,
                    endHook: value.endHook,
                    contract: value.contract
                )
            }
            let chapter = document.chapters[min(index, document.chapters.count - 1)]
            return EpisodePlan(
                number: index + 1,
                title: chapter.title,
                sourceChapterIDs: [chapter.id],
                plannedSceneCount: min(2, range.upperBound),
                openingHook: "危机在画面中直接发生",
                objective: "推进 \(chapter.title) 的核心冲突",
                reversal: "人物发现原先判断并不完整",
                endHook: "新证据出现，行动被迫中断",
                contract: EpisodeContract(
                    dominantConflict: chapter.title,
                    newInformation: ["章节事实待成稿呈现"],
                    visualHook: "可见冲突",
                    transitionFromPrevious: index == 0 ? "首集" : "承接上一集退出状态",
                    activePropThreads: [],
                    entryState: "冲突开始",
                    exitState: "冲突升级"
                )
            )
        }
    }

    private static func sourceText(for plan: EpisodePlan, document: NovelDocument) -> String {
        let selected = document.chapters.filter { plan.sourceChapterIDs.contains($0.id) }
        return selected.map { chapter in
            let content = chapter.content.count > 18_000
                ? String(chapter.content.prefix(18_000)) + "\n[长章其余内容已在故事圣经证据中汇总]"
                : chapter.content
            return "[\(chapter.id)] \(chapter.title)\n\(content)"
        }.joined(separator: "\n\n")
    }

    private static func sanitize(_ value: ChunkAnalysis, allowedChapterIDs: Set<String>) -> ChunkAnalysis {
        ChunkAnalysis(
            summary: value.summary,
            facts: value.facts,
            keyEvents: value.keyEvents,
            emotionalBeats: value.emotionalBeats,
            productionNotes: value.productionNotes,
            evidenceChapterIDs: value.evidenceChapterIDs.filter(allowedChapterIDs.contains)
        )
    }

    private static func sanitizeBible(
        _ bible: StoryBible,
        document: NovelDocument,
        characters: [CharacterProfile]
    ) -> StoryBible {
        let allowed = Set(document.chapters.map(\.id))
        let knownNames = Set(characters.map(\.targetName))
        return StoryBible(
            premise: renamed(bible.premise, characters),
            canonicalCharacters: bible.canonicalCharacters.map {
                CanonicalCharacter(
                    id: $0.id,
                    sourceNames: $0.sourceNames,
                    scriptName: knownNames.contains($0.scriptName) ? $0.scriptName : renamed($0.scriptName, characters),
                    role: $0.role,
                    relationships: $0.relationships.map { renamed($0, characters) },
                    evidenceChapterIDs: $0.evidenceChapterIDs.filter(allowed.contains)
                )
            },
            worldRules: bible.worldRules.map {
                WorldRule(
                    id: $0.id,
                    subject: renamed($0.subject, characters),
                    fact: renamed($0.fact, characters),
                    cause: renamed($0.cause, characters),
                    evidenceChapterIDs: $0.evidenceChapterIDs.filter(allowed.contains)
                )
            },
            propThreads: bible.propThreads,
            timeline: bible.timeline
        )
    }

    private static func makeQualityIssue(_ value: SeriesIssueDTO) -> QualityGateIssue {
        QualityGateIssue(
            id: UUID().uuidString,
            severity: QualityIssueSeverity(rawValue: value.severity) ?? .major,
            category: QualityIssueCategory(rawValue: value.category) ?? .continuity,
            episodeNumbers: value.episodeNumbers,
            evidence: value.evidence,
            repairInstruction: value.repairInstruction,
            resolved: false
        )
    }

    private static func renamed(_ value: String, _ characters: [CharacterProfile]) -> String {
        CharacterExtractor.applyRenames(value, characters: characters)
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard
            let data = try? JSONEncoder.scriptForge.encode(value),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static let systemBase = """
    你是中国竖屏微短剧工业化改编系统中的一个受限节点。严格读取上游资产，只输出当前 Schema 要求的数据；不输出分析过程，不虚构原文证据，不擅自改名。强情绪必须带来人物选择和后果，避免机械羞辱、重复退婚和只放狠话不行动。
    """

    private static let stringArray: [String: Any] = [
        "type": "array",
        "items": ["type": "string"],
    ]

    private static let namingSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "renames": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "sourceName": ["type": "string"],
                        "targetName": ["type": "string"],
                    ],
                    "required": ["sourceName", "targetName"],
                ],
            ],
        ],
        "required": ["renames"],
    ]

    private static let chunkSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "summary": ["type": "string"],
            "facts": stringArray,
            "keyEvents": stringArray,
            "emotionalBeats": stringArray,
            "productionNotes": stringArray,
            "evidenceChapterIDs": stringArray,
        ],
        "required": ["summary", "facts", "keyEvents", "emotionalBeats", "productionNotes", "evidenceChapterIDs"],
    ]

    private static let canonicalCharacterSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "id": ["type": "string"], "sourceNames": stringArray,
            "scriptName": ["type": "string"], "role": ["type": "string"],
            "relationships": stringArray, "evidenceChapterIDs": stringArray,
        ],
        "required": ["id", "sourceNames", "scriptName", "role", "relationships", "evidenceChapterIDs"],
    ]

    private static let worldRuleSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "id": ["type": "string"], "subject": ["type": "string"],
            "fact": ["type": "string"], "cause": ["type": "string"],
            "evidenceChapterIDs": stringArray,
        ],
        "required": ["id", "subject", "fact", "cause", "evidenceChapterIDs"],
    ]

    private static let propThreadSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "id": ["type": "string"], "name": ["type": "string"],
            "dramaticFunction": ["type": "string"], "introducedEpisode": ["type": "integer"],
            "payoffEpisode": ["type": "integer"], "currentState": ["type": "string"],
            "evidenceChapterIDs": stringArray,
        ],
        "required": ["id", "name", "dramaticFunction", "introducedEpisode", "payoffEpisode", "currentState", "evidenceChapterIDs"],
    ]

    private static let timelineSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "id": ["type": "string"], "order": ["type": "integer"],
            "location": ["type": "string"], "time": ["type": "string"],
            "participants": stringArray, "cause": ["type": "string"],
            "event": ["type": "string"], "effect": ["type": "string"],
            "evidenceChapterIDs": stringArray,
        ],
        "required": ["id", "order", "location", "time", "participants", "cause", "event", "effect", "evidenceChapterIDs"],
    ]

    private static let storyBibleSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "premise": ["type": "string"],
            "canonicalCharacters": ["type": "array", "items": canonicalCharacterSchema],
            "worldRules": ["type": "array", "items": worldRuleSchema],
            "propThreads": ["type": "array", "items": propThreadSchema],
            "timeline": ["type": "array", "items": timelineSchema],
        ],
        "required": ["premise", "canonicalCharacters", "worldRules", "propThreads", "timeline"],
    ]

    private static let episodeContractSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "dominantConflict": ["type": "string"], "newInformation": stringArray,
            "visualHook": ["type": "string"], "transitionFromPrevious": ["type": "string"],
            "activePropThreads": stringArray, "entryState": ["type": "string"],
            "exitState": ["type": "string"],
        ],
        "required": ["dominantConflict", "newInformation", "visualHook", "transitionFromPrevious", "activePropThreads", "entryState", "exitState"],
    ]

    private static func outlineSchema(episodeCount: Int, durationSeconds: Int) -> [String: Any] {
        let range = EpisodeBudget.sceneRange(durationSeconds: durationSeconds)
        let plan: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": [
                "number": ["type": "integer"], "title": ["type": "string"],
                "sourceChapterIDs": stringArray,
                "plannedSceneCount": ["type": "integer", "minimum": range.lowerBound, "maximum": range.upperBound],
                "openingHook": ["type": "string"], "objective": ["type": "string"],
                "reversal": ["type": "string"], "endHook": ["type": "string"],
                "contract": episodeContractSchema,
            ],
            "required": ["number", "title", "sourceChapterIDs", "plannedSceneCount", "openingHook", "objective", "reversal", "endHook", "contract"],
        ]
        return [
            "type": "object", "additionalProperties": false,
            "properties": [
                "logline": ["type": "string"], "genre": ["type": "string"],
                "themes": stringArray, "sourceFacts": stringArray,
                "episodes": ["type": "array", "minItems": episodeCount, "maxItems": episodeCount, "items": plan],
            ],
            "required": ["logline", "genre", "themes", "sourceFacts", "episodes"],
        ]
    }

    private static func episodeSchema(durationSeconds: Int) -> [String: Any] {
        let range = EpisodeBudget.sceneRange(durationSeconds: durationSeconds)
        let dialogue: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": ["speaker": ["type": "string"], "text": ["type": "string"]],
            "required": ["speaker", "text"],
        ]
        let scene: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": [
                "heading": ["type": "string"], "location": ["type": "string"],
                "action": ["type": "string"],
                "dialogue": ["type": "array", "items": dialogue],
            ],
            "required": ["heading", "location", "action", "dialogue"],
        ]
        return [
            "type": "object", "additionalProperties": false,
            "properties": [
                "scenes": [
                    "type": "array", "minItems": range.lowerBound,
                    "maxItems": range.upperBound, "items": scene,
                ],
            ],
            "required": ["scenes"],
        ]
    }

    private static let semanticAuditSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "score": ["type": "integer", "minimum": 0, "maximum": 100],
            "passed": ["type": "boolean"], "issues": stringArray,
        ],
        "required": ["score", "passed", "issues"],
    ]

    private static let seriesAuditSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "issues": [
                "type": "array",
                "items": [
                    "type": "object", "additionalProperties": false,
                    "properties": [
                        "severity": ["type": "string", "enum": ["blocker", "major", "minor"]],
                        "category": ["type": "string", "enum": ["sourceFidelity", "continuity", "character", "pacing", "hook", "dialogue", "production", "compliance"]],
                        "episodeNumbers": ["type": "array", "items": ["type": "integer"]],
                        "evidence": ["type": "string"], "repairInstruction": ["type": "string"],
                    ],
                    "required": ["severity", "category", "episodeNumbers", "evidence", "repairInstruction"],
                ],
            ],
        ],
        "required": ["issues"],
    ]
}
