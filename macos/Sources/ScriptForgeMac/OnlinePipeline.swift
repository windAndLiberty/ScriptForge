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
        let outputLanguage = AppLanguage.detect(in: document.rawText)
        let namingRule = outputLanguage == .english
            ? "Generate natural, distinct English-language screenplay names. Do not transliterate them into Chinese."
            : "Generate natural, distinct Simplified-Chinese screenplay names."
        let response: NamingResponse = try await client.structured(
            stage: .characterNaming,
            instructions: instruction(
                prompts: PromptAssets.mergedInstruction(["character-naming"], assets: prompts),
                outputLanguage: outputLanguage
            ) + "\n\n" + namingRule,
            input: """
            Generate screenplay names for all of the following characters in one pass. Preserve every sourceName exactly:
            \(characters.map { "- \($0.sourceName): role=\($0.role); occurrences=\($0.occurrences); traits=\($0.traits.joined(separator: ", "))" }.joined(separator: "\n"))
            Story context: \(document.title); \(document.intro.prefix(500))
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
        interfaceLanguage: AppLanguage = .chinese,
        progress: @escaping (PipelinePhase, String, Double) -> Void
    ) async throws -> AdaptationResult {
        guard CharacterExtractor.validate(characters) else { throw PipelineError.invalidNames }
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let outputLanguage = options.outputLanguage(for: document)
        let evidenceInstruction = instruction(
            prompts: PromptAssets.mergedInstruction(
            ["story-evidence"],
            assets: prompts
            ),
            outputLanguage: outputLanguage
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
                interfaceLanguage == .english
                    ? "Extracting chapter evidence \(index + 1) / \(chapterGroups.count)"
                    : "正在抽取章节证据 \(index + 1) / \(chapterGroups.count)",
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

        progress(
            .bible,
            interfaceLanguage == .english
                ? "Building characters, world rules, and timeline"
                : "正在建立人物、世界规则与时间线",
            0.31
        )
        let bibleResponse: StoryBibleResponse = try await client.structured(
            stage: .storyBible,
            instructions: instruction(
                prompts: PromptAssets.mergedInstruction(["story-bible"], assets: prompts),
                outputLanguage: outputLanguage
            ) + "\n\nThe screenplay may use only these locked character names: \(characters.map(\.targetName).joined(separator: ", ")).",
            input: """
            [Character Mapping]
            \(characters.map {
                outputLanguage == .english
                    ? "\($0.sourceName) -> \($0.targetName) (\($0.resolvedRole(for: .english)))"
                    : "\($0.sourceName) → \($0.targetName)（\($0.role)）"
            }.joined(separator: "\n"))

            [Chapter Evidence]
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

        progress(
            .outline,
            interfaceLanguage == .english
                ? "Planning episode contracts and dynamic scenes"
                : "正在规划全剧分集契约与动态场次",
            0.4
        )
        let outline: OutlineResponse = try await client.structured(
            stage: .episodeOutline,
            instructions: instruction(
                prompts: PromptAssets.mergedInstruction(["episode-planning"], assets: prompts),
                outputLanguage: outputLanguage
            ) + """

            Plan exactly \(options.episodeCount) episodes, each lasting \(options.durationSeconds) seconds.
            Let the story determine scene count within \(EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds).lowerBound)–\(EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds).upperBound) scenes per episode.
            """,
            input: """
            [Story Bible]\n\(json(bible))
            [Chapter Evidence]\n\(json(analyses))
            [Genre]\n\(options.resolvedGenre(for: outputLanguage))
            [Tone]\n\(options.resolvedTone(for: outputLanguage))
            [Trend Strategy]\n\(options.trendPreset.resolvedValue(for: outputLanguage))
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
                interfaceLanguage == .english
                    ? "Drafting episode \(index + 1) / \(plans.count)"
                    : "正在生成第 \(index + 1) / \(plans.count) 集",
                0.48 + Double(index) / Double(max(1, plans.count)) * 0.31
            )
            let source = sourceText(for: plan, document: document)
            let previous = episodes.last.map {
                "Previous episode exit state: \($0.contract.exitState)\nPrevious episode cliffhanger: \($0.endHook)"
            } ?? "Opening episode: establish a visible conflict within the first five seconds."
            let draft: EpisodeDraft = try await client.structured(
                stage: .episodeDraft,
                instructions: draftInstruction(
                    options: options,
                    characters: characters,
                    prompts: prompts,
                    plannedSceneCount: plan.plannedSceneCount,
                    outputLanguage: outputLanguage
                ),
                input: """
                [Story Bible]\n\(json(bible))
                [Episode Contract]\n\(json(plan))
                [Continuity]\n\(previous)
                [Source Evidence]\n\(source)
                """,
                name: "episode_\(plan.number)",
                schema: episodeSchema(durationSeconds: options.durationSeconds)
            )
            var episode = makeEpisode(
                plan: plan,
                draft: draft,
                characters: characters,
                outputLanguage: outputLanguage
            )
            let completeness = EpisodeBudget.assess(
                scenes: episode.scenes,
                durationSeconds: options.durationSeconds,
                language: outputLanguage
            )
            let semantic = try await semanticAudit(
                episode: episode,
                bible: bible,
                plan: plan,
                prompts: prompts,
                client: client,
                outputLanguage: outputLanguage
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
                    client: client,
                    outputLanguage: outputLanguage
                )
                let repairedCompleteness = EpisodeBudget.assess(
                    scenes: repaired.scenes,
                    durationSeconds: options.durationSeconds,
                    language: outputLanguage
                )
                let repairedSemantic = try await semanticAudit(
                    episode: repaired,
                    bible: bible,
                    plan: plan,
                    prompts: prompts,
                    client: client,
                    outputLanguage: outputLanguage
                )
                if repairedCompleteness.passed && repairedSemantic.passed {
                    var accepted = repaired
                    accepted.runtime = repairedCompleteness.runtime
                    accepted.semanticAudit = repairedSemantic
                    accepted.content = OfflinePipeline.render(accepted, language: outputLanguage)
                    episode = accepted
                    acceptedRepairs += 1
                }
            }
            episode.content = OfflinePipeline.render(episode, language: outputLanguage)
            episodes.append(episode)
        }

        progress(
            .quality,
            interfaceLanguage == .english
                ? "Running overlapping cross-episode review"
                : "正在执行跨集重叠窗口终审",
            0.82
        )
        let initialAudit = try await auditSeries(
            episodes: episodes,
            bible: bible,
            prompts: prompts,
            client: client,
            outputLanguage: outputLanguage
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
                    client: client,
                    outputLanguage: outputLanguage
                )
                let oldScore = EpisodeBudget.assess(
                    scenes: episodes[index].scenes,
                    durationSeconds: options.durationSeconds,
                    language: outputLanguage
                ).score
                let newAssessment = EpisodeBudget.assess(
                    scenes: repaired.scenes,
                    durationSeconds: options.durationSeconds,
                    language: outputLanguage
                )
                let verification = try await semanticAudit(
                    episode: repaired,
                    bible: bible,
                    plan: plan,
                    prompts: prompts,
                    client: client,
                    outputLanguage: outputLanguage
                )
                if newAssessment.passed && newAssessment.score >= oldScore && verification.passed {
                    var accepted = repaired
                    accepted.runtime = newAssessment.runtime
                    accepted.semanticAudit = verification
                    accepted.content = OfflinePipeline.render(accepted, language: outputLanguage)
                    episodes[index] = accepted
                    acceptedRepairs += 1
                }
            }
        }

        progress(
            .quality,
            interfaceLanguage == .english
                ? "Rechecking continuity after repairs"
                : "正在复验修订后的全剧连续性",
            0.93
        )
        let finalAudit = try await auditSeries(
            episodes: episodes,
            bible: bible,
            prompts: prompts,
            client: client,
            outputLanguage: outputLanguage
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
            auditedWindows: auditedWindows,
            outputLanguage: outputLanguage
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
        client: LLMClient,
        outputLanguage: AppLanguage
    ) async throws -> EpisodeSemanticAudit {
        let response: SemanticAuditResponse = try await client.structured(
            stage: .episodeSemanticAudit,
            instructions: instruction(
                prompts: PromptAssets.mergedInstruction(["quality-gate"], assets: prompts),
                outputLanguage: outputLanguage
            ),
            input: """
            [Story Bible]\n\(json(bible))
            [Episode Contract]\n\(json(plan))
            [Candidate Draft]\n\(episode.content.isEmpty ? OfflinePipeline.render(episode, language: outputLanguage) : episode.content)
            Check only whether this episode is faithful to the evidence, character motivations are credible, the conflict genuinely advances, and the hooks are visible and shootable.
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
        client: LLMClient,
        outputLanguage: AppLanguage
    ) async throws -> Episode {
        let draft: EpisodeDraft = try await client.structured(
            stage: .episodeRepair,
            instructions: draftInstruction(
                options: options,
                characters: characters,
                prompts: prompts,
                plannedSceneCount: plan.plannedSceneCount,
                outputLanguage: outputLanguage
            ) + "\n\nRepair only the listed major issues. Preserve valid conflicts, facts, and effective dialogue.",
            input: """
            [Story Bible]\n\(json(bible))
            [Episode Contract]\n\(json(plan))
            [Source Evidence]\n\(source)
            [Current Draft]\n\(episode.content.isEmpty ? OfflinePipeline.render(episode, language: outputLanguage) : episode.content)
            [Required Repairs]\n- \(issues.joined(separator: "\n- "))
            """,
            name: "episode_repair_\(episode.number)",
            schema: episodeSchema(durationSeconds: options.durationSeconds)
        )
        return makeEpisode(
            plan: plan,
            draft: draft,
            characters: characters,
            outputLanguage: outputLanguage
        )
    }

    private static func auditSeries(
        episodes: [Episode],
        bible: StoryBible,
        prompts: [PromptAsset],
        client: LLMClient,
        outputLanguage: AppLanguage
    ) async throws -> SeriesAuditResponse {
        var issues: [SeriesIssueDTO] = []
        for window in seriesWindows(episodes) {
            let response: SeriesAuditResponse = try await client.structured(
                stage: .seriesQualityAudit,
                instructions: instruction(
                    prompts: PromptAssets.mergedInstruction(["quality-gate"], assets: prompts),
                    outputLanguage: outputLanguage
                ) + """

                Report only locatable blocker, major, or minor issues. Focus on the reasons for transitions between episodes, character relationships and names, ability rules, repeated central conflicts, and foreshadowing that disappears without explanation.
                """,
                input: "[Story Bible]\n\(json(bible))\n[Consecutive Episodes]\n\(window.map(\.content).joined(separator: "\n\n"))",
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

    static func draftInstruction(
        options: AdaptationOptions,
        characters: [CharacterProfile],
        prompts: [PromptAsset],
        plannedSceneCount: Int,
        outputLanguage: AppLanguage = .chinese
    ) -> String {
        let budget = EpisodeBudget.budget(
            durationSeconds: options.durationSeconds,
            language: outputLanguage
        )
        let unitName = outputLanguage == .english ? "English dialogue words" : "effective spoken Chinese characters"
        return instruction(
            prompts: PromptAssets.mergedInstruction(["episode-drafting"], assets: prompts),
            outputLanguage: outputLanguage
        ) + """

        Use only these locked character names: \(characters.map(\.targetName).joined(separator: ", ")).
        Target approximately \(options.durationSeconds) seconds. Let the story determine scene count within \(budget.sceneRange.lowerBound)–\(budget.sceneRange.upperBound) scenes. The episode plan recommends \(plannedSceneCount) scenes, but never split scenes merely to meet a count.
        HARD COMPLETENESS BUDGET: produce \(budget.dialogueLines.lowerBound)–\(budget.dialogueLines.upperBound) short dialogue lines and \(budget.spokenCharacters.lowerBound)–\(budget.spokenCharacters.upperBound) \(unitName) across the entire episode. Count before returning. A draft below either lower bound is incomplete. These are episode-wide budgets, not minimums for each scene.
        Every scene must define its time and setting, location, shootable action, and dialogue array. Never output a source character name that has been replaced.
        """
    }

    private static func makeEpisode(
        plan: EpisodePlan,
        draft: EpisodeDraft,
        characters: [CharacterProfile],
        outputLanguage: AppLanguage
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
        episode.runtime = EpisodeBudget.estimateRuntime(scenes: scenes, language: outputLanguage)
        episode.content = OfflinePipeline.render(episode, language: outputLanguage)
        return episode
    }

    private static func normalizePlans(
        _ source: [EpisodePlan],
        document: NovelDocument,
        options: AdaptationOptions
    ) -> [EpisodePlan] {
        let range = EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds)
        let language = options.outputLanguage(for: document)
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
                openingHook: language == .english ? "The crisis begins visibly on screen" : "危机在画面中直接发生",
                objective: language == .english ? "Advance the central conflict of \(chapter.title)" : "推进 \(chapter.title) 的核心冲突",
                reversal: language == .english ? "A character discovers that the original judgment was incomplete" : "人物发现原先判断并不完整",
                endHook: language == .english ? "New evidence interrupts the action" : "新证据出现，行动被迫中断",
                contract: EpisodeContract(
                    dominantConflict: chapter.title,
                    newInformation: [language == .english ? "Source facts must be dramatized in the draft" : "章节事实待成稿呈现"],
                    visualHook: language == .english ? "Visible conflict" : "可见冲突",
                    transitionFromPrevious: language == .english
                        ? (index == 0 ? "Opening episode" : "Continue from the previous exit state")
                        : (index == 0 ? "首集" : "承接上一集退出状态"),
                    activePropThreads: [],
                    entryState: language == .english ? "Conflict begins" : "冲突开始",
                    exitState: language == .english ? "Conflict escalates" : "冲突升级"
                )
            )
        }
    }

    private static func sourceText(for plan: EpisodePlan, document: NovelDocument) -> String {
        let selected = document.chapters.filter { plan.sourceChapterIDs.contains($0.id) }
        return selected.map { chapter in
            let content = chapter.content.count > 18_000
                ? String(chapter.content.prefix(18_000)) + "\n[The remainder of this long chapter is summarized in the story-bible evidence.]"
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

    static let systemBase = """
    You are a constrained node in an industrial vertical micro-drama adaptation workflow. Read upstream assets strictly and output only data required by the current JSON Schema. Do not reveal hidden reasoning, fabricate source evidence, or rename characters without authorization. Strong emotion must cause a character choice and a consequence; avoid mechanical humiliation, repetitive engagement-cancellation plots, and threats without action.
    """

    static func instruction(prompts: String, outputLanguage: AppLanguage) -> String {
        systemBase + "\n\n" + prompts + """


        OUTPUT LANGUAGE CONTRACT: Write every natural-language output value exclusively in \(outputLanguage.promptName). Preserve proper names, verbatim source excerpts, and evidence IDs in their original form. Do not translate evidence IDs or mix languages in labels, summaries, plans, dialogue, actions, audits, or repair instructions. This final contract overrides language preferences in editable prompt assets, while leaving privacy, source fidelity, and JSON structure constraints unchanged.
        """
    }

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
