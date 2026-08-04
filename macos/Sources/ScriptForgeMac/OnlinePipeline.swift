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
            ä¸ºä»¥ä¸‹äººç‰©ä¸€æ¬¡æ€§ç”Ÿæˆå‰§æœ¬æ–°åã€‚ä¿ç•™ sourceName åŽŸæ ·ï¼š
            \(characters.map { "- \($0.sourceName)ï¼š\($0.role)ï¼Œå‡ºçŽ° \($0.occurrences) æ¬¡ï¼Œç‰¹å¾ \($0.traits.joined(separator: "ã€"))" }.joined(separator: "\n"))
            å°è¯´ç±»åž‹æç¤ºï¼š\(document.title)ï¼›\(document.intro.prefix(500))
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
                "æ­£åœ¨æŠ½å–ç« èŠ‚è¯æ® \(index + 1) / \(chapterGroups.count)",
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

        progress(.bible, "æ­£åœ¨å»ºç«‹äººç‰©ã€ä¸–ç•Œè§„åˆ™ä¸Žæ—¶é—´çº¿", 0.31)
        let bibleResponse: StoryBibleResponse = try await client.structured(
            stage: .storyBible,
            instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(
                ["story-bible"],
                assets: prompts
            ) + "\n\nå‰§æœ¬åªèƒ½ä½¿ç”¨é”å®šæ–°åï¼š\(characters.map(\.targetName).joined(separator: "ã€"))ã€‚",
            input: """
            ã€äººç‰©æ˜ å°„ã€‘
            \(characters.map { "\($0.sourceName) â†’ \($0.targetName)ï¼ˆ\($0.role)ï¼‰" }.joined(separator: "\n"))

            ã€ç« èŠ‚è¯æ®ã€‘
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

        progress(.outline, "æ­£åœ¨è§„åˆ’å…¨å‰§åˆ†é›†å¥‘çº¦ä¸ŽåŠ¨æ€åœºæ¬¡", 0.4)
        let outline: OutlineResponse = try await client.structured(
            stage: .episodeOutline,
            instructions: systemBase + "\n\n" + PromptAssets.mergedInstruction(
                ["episode-planning"],
                assets: prompts
            ) + """

            å¿…é¡»è§„åˆ’æ°å¥½ \(options.episodeCount) é›†ï¼›æ¯é›†æ—¶é•¿ \(options.durationSeconds) ç§’ã€‚
            åœºæ¬¡æ•°ç”±å‰§æƒ…å†³å®šï¼Œå…è®¸èŒƒå›´ \(EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds).lowerBound)â€“\(EpisodeBudget.sceneRange(durationSeconds: options.durationSeconds).upperBound) åœºã€‚
            """,
            input: """
            ã€æ•…äº‹åœ£ç»ã€‘\(json(bible))
            ã€ç« èŠ‚è¯æ®ã€‘\(json(analyses))
            ã€ç±»åž‹ã€‘\(options.genre)
            ã€åŸºè°ƒã€‘\(options.tone)
            ã€è¶‹åŠ¿ç­–ç•¥ã€‘\(options.trendPreset.rawValue)
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
                "æ­£åœ¨ç”Ÿæˆç¬¬ \(index + 1) / \(plans.count) é›†",
                0.48 + Double(index) / Double(max(1, plans.count)) * 0.31
            )
            let source = sourceText(for: plan, document: document)
            let previous = episodes.last.map {
                "ä¸Šä¸€é›†é€€å‡ºçŠ¶æ€ï¼š\($0.contract.exitState)\nä¸Šä¸€é›†å¡ç‚¹ï¼š\($0.endHook)"
            } ?? "é¦–é›†ï¼šå‰5ç§’ç›´æŽ¥å»ºç«‹è§†è§‰å†²çª"
            let draft: EpisodeDraft = try await client.structured(
                stage: .episodeDraft,
                instructions: draftInstruction(
                    options: options,
                    characters: characters,
                    prompts: prompts,
                    plannedSceneCount: plan.plannedSceneCount
                ),
                input: """
                ã€æ•…äº‹åœ£ç»ã€‘\(json(bible))
                ã€æœ¬é›†å¥‘çº¦ã€‘\(json(plan))
                ã€è¿žç»­æ€§ã€‘\(previous)
                ã€å¯¹åº”åŽŸæ–‡ã€‘\(source)
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

        progress(.quality, "æ­£åœ¨æ‰§è¡Œè·¨é›†é‡å çª—å£ç»ˆå®¡", 0.82)
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
                    issues: related.map { "\($0.evidence)ï¼š\($0.repairInstruction)" },
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

        progress(.quality, "æ­£åœ¨å¤éªŒä¿®è®¢åŽçš„å…¨å‰§è¿žç»­æ€§", 0.93)
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
            input:×Ýö¶‰žËkºwµç}Õ¹ÐèÁ±…¸¹Á±…¹¹•‘M•¹•½Õ¹Ð°(€€€€€€€€€€€½Á•¹¥¹!½½¬èÉ•¹…µ•¡Á±…¸¹½Á•¹¥¹!½½¬°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€½‰©•Ñ¥Ù”èÉ•¹…µ•¡Á±…¸¹½‰©•Ñ¥Ù”°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€É•Ù•ÉÍ…°èÉ•¹…µ•¡Á±…¸¹É•Ù•ÉÍ…°°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€•¹‘!½½¬èÉ•¹…µ•¡Á±…¸¹•¹‘!½½¬°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€½¹ÑÉ…ÐèÁ±…¸¹½¹ÑÉ…Ð°(€€€€€€€€€€€ÉÕ¹Ñ¥µ”è¹¥°°(€€€€€€€€€€€Í•µ…¹Ñ¥Õ‘¥Ðè¹¥°°(€€€€€€€€€€€Í•¹•ÌèÍ•¹•Ì°(€€€€€€€€€€€½¹Ñ•¹Ðè€ˆˆ(€€€€€€€€¤(€€€€€€€•Á¥Í½‘”¹ÉÕ¹Ñ¥µ”€ôÁ¥Í½‘•	Õ‘•Ð¹•ÍÑ¥µ…Ñ•IÕ¹Ñ¥µ”¡Í•¹•ÌèÍ•¹•Ì¤(€€€€€€€•Á¥Í½‘”¹½¹Ñ•¹Ð€ô=™™±¥¹•A¥Á•±¥¹”¹É•¹‘•È¡•Á¥Í½‘”¤(€€€€€€€É•ÑÕÉ¸•Á¥Í½‘”(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹Œ¹½Éµ…±¥é•A±…¹Ì (€€€€€€€|Í½ÕÉ”èmÁ¥Í½‘•A±…¹t°(€€€€€€€‘½Õµ•¹Ðè9½Ù•±½Õµ•¹Ð°(€€€€€€€½ÁÑ¥½¹Ìè‘…ÁÑ…Ñ¥½¹=ÁÑ¥½¹Ì(€€€€¤€´ømÁ¥Í½‘•A±…¹tì(€€€€€€€±•ÐÉ…¹”€ôÁ¥Í½‘•	Õ‘•Ð¹Í•¹•I…¹”¡‘ÕÉ…Ñ¥½¹M•½¹‘Ìè½ÁÑ¥½¹Ì¹‘ÕÉ…Ñ¥½¹M•½¹‘Ì¤(€€€€€€€É•ÑÕÉ¸€ À¸¸ñ½ÁÑ¥½¹Ì¹•Á¥Í½‘•½Õ¹Ð¤¹µ…Àì¥¹‘•à¥¸(€€€€€€€€€€€¥˜Í½ÕÉ”¹¥¹‘¥•Ì¹½¹Ñ…¥¹Ì¡¥¹‘•à¤ì(€€€€€€€€€€€€€€€±•ÐÙ…±Õ”€ôÍ½ÕÉ•m¥¹‘•át(€€€€€€€€€€€€€€€±•Ð%Ì€ôÙ…±Õ”¹Í½ÕÉ•¡…ÁÑ•É%Ì¹™¥±Ñ•Èì¥¥¸‘½Õµ•¹Ð¹¡…ÁÑ•ÉÌ¹½¹Ñ…¥¹Ì¡Ý¡•É”èì€À¹¥€ôô¥ô¤ô(€€€€€€€€€€€€€€€É•ÑÕÉ¸Á¥Í½‘•A±…¸ (€€€€€€€€€€€€€€€€€€€¹Õµ‰•Èè¥¹‘•à€¬€Ä°(€€€€€€€€€€€€€€€€€€€Ñ¥Ñ±”èÙ…±Õ”¹Ñ¥Ñ±”°(€€€€€€€€€€€€€€€€€€€Í½ÕÉ•¡…ÁÑ•É%Ìè%Ì¹¥ÍµÁÑä€üm‘½Õµ•¹Ð¹¡…ÁÑ•ÉÍmµ¥¸¡¥¹‘•à°‘½Õµ•¹Ð¹¡…ÁÑ•ÉÌ¹½Õ¹Ð€´€Ä¥t¹¥‘t€è%Ì°(€€€€€€€€€€€€€€€€€€€Á±…¹¹•‘M•¹•½Õ¹Ðèµ¥¸¡É…¹”¹ÕÁÁ•É	½Õ¹°µ…à¡É…¹”¹±½Ý•É	½Õ¹°Ù…±Õ”¹Á±…¹¹•‘M•¹•½Õ¹Ð¤¤°(€€€€€€€€€€€€€€€€€€€½Á•¹¥¹!½½¬èÙ…±Õ”¹½Á•¹¥¹!½½¬°(€€€€€€€€€€€€€€€€€€€½‰©•Ñ¥Ù”èÙ…±Õ”¹½‰©•Ñ¥Ù”°(€€€€€€€€€€€€€€€€€€€É•Ù•ÉÍ…°èÙ…±Õ”¹É•Ù•ÉÍ…°°(€€€€€€€€€€€€€€€€€€€•¹‘!½½¬èÙ…±Õ”¹•¹‘!½½¬°(€€€€€€€€€€€€€€€€€€€½¹ÑÉ…ÐèÙ…±Õ”¹½¹ÑÉ…Ð(€€€€€€€€€€€€€€€€¤(€€€€€€€€€€€ô(€€€€€€€€€€€±•Ð¡…ÁÑ•È€ô‘½Õµ•¹Ð¹¡…ÁÑ•ÉÍmµ¥¸¡¥¹‘•à°‘½Õµ•¹Ð¹¡…ÁÑ•ÉÌ¹½Õ¹Ð€´€Ä¥t(€€€€€€€€€€€É•ÑÕÉ¸Á¥Í½‘•A±…¸ (€€€€€€€€€€€€€€€¹Õµ‰•Èè¥¹‘•à€¬€Ä°(€€€€€€€€€€€€€€€Ñ¥Ñ±”è¡…ÁÑ•È¹Ñ¥Ñ±”°(€€€€€€€€€€€€€€€Í½ÕÉ•¡…ÁÑ•É%Ìèm¡…ÁÑ•È¹¥‘t°(€€€€€€€€€€€€€€€Á±…¹¹•‘M•¹•½Õ¹Ðèµ¥¸ È°É…¹”¹ÕÁÁ•É	½Õ¹¤°(€€€€€€€€€€€€€€€½Á•¹¥¹!½½¬è€‹–6Çšrë–r£žRï¦v‹’â·žnÓš:—–>GžR|ˆ°(€€€€€€€€€€€€€€€½‰©•Ñ¥Ù”è€‹š:£¢þlp¡¡…ÁÑ•È¹Ñ¥Ñ±”¤ƒžjš‚ã–þ–Ëžªˆ°(€€€€€€€€€€€€€€€É•Ù•ÉÍ…°è€‹’êëž&§–>Gž:Ã–:–#–"“šZ·–æÛ’â7–º3šVÐˆ°(€€€€€€€€€€€€€€€•¹‘!½½¬è€‹šZÃ¢¾š6»–ëž:Ã¾ò3¢†3–*£¢Š¯¢þ¯’â·šZ´ˆ°(€€€€€€€€€€€€€€€½¹ÑÉ…ÐèÁ¥Í½‘•½¹ÑÉ…Ð (€€€€€€€€€€€€€€€€€€€‘½µ¥¹…¹Ñ½¹™±¥Ðè¡…ÁÑ•È¹Ñ¥Ñ±”°(€€€€€€€€€€€€€€€€€€€¹•Ý%¹™½Éµ…Ñ¥½¸èl‹ž®ƒ¢*’ê/–º{–úš"Cž¢ÿ–F#ž:À‰t°(€€€€€€€€€€€€€€€€€€€Ù¥ÍÕ…±!½½¬è€‹–>¿¢ž–Ëžªˆ°(€€€€€€€€€€€€€€€€€€€ÑÉ…¹Í¥Ñ¥½¹É½µAÉ•Ù¥½ÕÌè¥¹‘•à€ôô€À€ü€‹¦š[¦nˆ€è€‹š&ÿš:—’â+’â¦n¦–ëž*Ûšˆ°(€€€€€€€€€€€€€€€€€€€…Ñ¥Ù•AÉ½ÁQ¡É•…‘Ìèmt°(€€€€€€€€€€€€€€€€€€€•¹ÑÉåMÑ…Ñ”è€‹–Ëžª–ò–ž,ˆ°(€€€€€€€€€€€€€€€€€€€•á¥ÑMÑ…Ñ”è€‹–Ëžª–6žêœˆ(€€€€€€€€€€€€€€€€¤(€€€€€€€€€€€€¤(€€€€€€€ô(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹ŒÍ½ÕÉ•Q•áÐ¡™½ÈÁ±…¸èÁ¥Í½‘•A±…¸°‘½Õµ•¹Ðè9½Ù•±½Õµ•¹Ð¤€´øMÑÉ¥¹œì(€€€€€€€±•ÐÍ•±•Ñ•€ô‘½Õµ•¹Ð¹¡…ÁÑ•ÉÌ¹™¥±Ñ•ÈìÁ±…¸¹Í½ÕÉ•¡…ÁÑ•É%Ì¹½¹Ñ…¥¹Ì À¹¥¤ô(€€€€€€€É•ÑÕÉ¸Í•±•Ñ•¹µ…Àì¡…ÁÑ•È¥¸(€€€€€€€€€€€±•Ð½¹Ñ•¹Ð€ô¡…ÁÑ•È¹½¹Ñ•¹Ð¹½Õ¹Ð€ø€Äá|ÀÀÀ(€€€€€€€€€€€€€€€€üMÑÉ¥¹œ¡¡…ÁÑ•È¹½¹Ñ•¹Ð¹ÁÉ•™¥à Äá|ÀÀÀ¤¤€¬€‰q¹o¦Vÿž®ƒ–Û’ög––ºç–ÞË–r£šV’ê/–ržî?¢¾š6»’â·šÆšítˆ(€€€€€€€€€€€€€€€€è¡…ÁÑ•È¹½¹Ñ•¹Ð(€€€€€€€€€€€É•ÑÕÉ¸€‰mp¡¡…ÁÑ•È¹¥¥tp¡¡…ÁÑ•È¹Ñ¥Ñ±”¥q¹p¡½¹Ñ•¹Ð¤ˆ(€€€€€€€ô¹©½¥¹•¡Í•Á…É…Ñ½Èè€‰q¹q¸ˆ¤(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹ŒÍ…¹¥Ñ¥é”¡|Ù…±Õ”è¡Õ¹­¹…±åÍ¥Ì°…±±½Ý•‘¡…ÁÑ•É%ÌèM•ÐñMÑÉ¥¹œø¤€´ø¡Õ¹­¹…±åÍ¥Ìì(€€€€€€€¡Õ¹­¹…±åÍ¥Ì (€€€€€€€€€€€ÍÕµµ…ÉäèÙ…±Õ”¹ÍÕµµ…Éä°(€€€€€€€€€€€™…ÑÌèÙ…±Õ”¹™…ÑÌ°(€€€€€€€€€€€­•åÙ•¹ÑÌèÙ…±Õ”¹­•åÙ•¹ÑÌ°(€€€€€€€€€€€•µ½Ñ¥½¹…±	•…ÑÌèÙ…±Õ”¹•µ½Ñ¥½¹…±	•…ÑÌ°(€€€€€€€€€€€ÁÉ½‘ÕÑ¥½¹9½Ñ•ÌèÙ…±Õ”¹ÁÉ½‘ÕÑ¥½¹9½Ñ•Ì°(€€€€€€€€€€€•Ù¥‘•¹•¡…ÁÑ•É%ÌèÙ…±Õ”¹•Ù¥‘•¹•¡…ÁÑ•É%Ì¹™¥±Ñ•È¡…±±½Ý•‘¡…ÁÑ•É%Ì¹½¹Ñ…¥¹Ì¤(€€€€€€€€¤(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹ŒÍ…¹¥Ñ¥é•	¥‰±” (€€€€€€€|‰¥‰±”èMÑ½Éå	¥‰±”°(€€€€€€€‘½Õµ•¹Ðè9½Ù•±½Õµ•¹Ð°(€€€€€€€¡…É…Ñ•ÉÌèm¡…É…Ñ•ÉAÉ½™¥±•t(€€€€¤€´øMÑ½Éå	¥‰±”ì(€€€€€€€±•Ð…±±½Ý•€ôM•Ð¡‘½Õµ•¹Ð¹¡…ÁÑ•ÉÌ¹µ…À¡p¹¥¤¤(€€€€€€€±•Ð­¹½Ý¹9…µ•Ì€ôM•Ð¡¡…É…Ñ•ÉÌ¹µ…À¡p¹Ñ…É•Ñ9…µ”¤¤(€€€€€€€É•ÑÕÉ¸MÑ½Éå	¥‰±” (€€€€€€€€€€€ÁÉ•µ¥Í”èÉ•¹…µ•¡‰¥‰±”¹ÁÉ•µ¥Í”°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€…¹½¹¥…±¡…É…Ñ•ÉÌè‰¥‰±”¹…¹½¹¥…±¡…É…Ñ•ÉÌ¹µ…Àì(€€€€€€€€€€€€€€€…¹½¹¥…±¡…É…Ñ•È (€€€€€€€€€€€€€€€€€€€¥è€À¹¥°(€€€€€€€€€€€€€€€€€€€Í½ÕÉ•9…µ•Ìè€À¹Í½ÕÉ•9…µ•Ì°(€€€€€€€€€€€€€€€€€€€ÍÉ¥ÁÑ9…µ”è­¹½Ý¹9…µ•Ì¹½¹Ñ…¥¹Ì À¹ÍÉ¥ÁÑ9…µ”¤€ü€À¹ÍÉ¥ÁÑ9…µ”€èÉ•¹…µ• À¹ÍÉ¥ÁÑ9…µ”°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€€€€€€€€€É½±”è€À¹É½±”°(€€€€€€€€€€€€€€€€€€€É•±…Ñ¥½¹Í¡¥ÁÌè€À¹É•±…Ñ¥½¹Í¡¥ÁÌ¹µ…ÀìÉ•¹…µ• À°¡…É…Ñ•ÉÌ¤ô°(€€€€€€€€€€€€€€€€€€€•Ù¥‘•¹•¡…ÁÑ•É%Ìè€À¹•Ù¥‘•¹•¡…ÁÑ•É%Ì¹™¥±Ñ•È¡…±±½Ý•¹½¹Ñ…¥¹Ì¤(€€€€€€€€€€€€€€€€¤(€€€€€€€€€€€ô°(€€€€€€€€€€€Ý½É±‘IÕ±•Ìè‰¥‰±”¹Ý½É±‘IÕ±•Ì¹µ…Àì(€€€€€€€€€€€€€€€]½É±‘IÕ±” (€€€€€€€€€€€€€€€€€€€¥è€À¹¥°(€€€€€€€€€€€€€€€€€€€ÍÕ‰©•ÐèÉ•¹…µ• À¹ÍÕ‰©•Ð°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€€€€€€€€€™…ÐèÉ•¹…µ• À¹™…Ð°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€€€€€€€€€…ÕÍ”èÉ•¹…µ• À¹…ÕÍ”°¡…É…Ñ•ÉÌ¤°(€€€€€€€€€€€€€€€€€€€•Ù¥‘•¹•¡…ÁÑ•É%Ìè€À¹•Ù¥‘•¹•¡…ÁÑ•É%Ì¹™¥±Ñ•È¡…±±½Ý•¹½¹Ñ…¥¹Ì¤(€€€€€€€€€€€€€€€€¤(€€€€€€€€€€€ô°(€€€€€€€€€€€ÁÉ½ÁQ¡É•…‘Ìè‰¥‰±”¹ÁÉ½ÁQ¡É•…‘Ì°(€€€€€€€€€€€Ñ¥µ•±¥¹”è‰¥‰±”¹Ñ¥µ•±¥¹”(€€€€€€€€¤(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹Œµ…­•EÕ…±¥Ñå%ÍÍÕ”¡|Ù…±Õ”èM•É¥•Í%ÍÍÕ•Q<¤€´øEÕ…±¥Ñå…Ñ•%ÍÍÕ”ì(€€€€€€€EÕ…±¥Ñå…Ñ•%ÍÍÕ” (€€€€€€€€€€€¥èUU% ¤¹ÕÕ¥‘MÑÉ¥¹œ°(€€€€€€€€€€€Í•Ù•É¥ÑäèEÕ…±¥Ñå%ÍÍÕ•M•Ù•É¥Ñä¡É…ÝY…±Õ”èÙ…±Õ”¹Í•Ù•É¥Ñä¤€üü€¹µ…©½È°(€€€€€€€€€€€…Ñ•½ÉäèEÕ…±¥Ñå%ÍÍÕ•…Ñ•½Éä¡É…ÝY…±Õ”èÙ…±Õ”¹…Ñ•½Éä¤€üü€¹½¹Ñ¥¹Õ¥Ñä°(€€€€€€€€€€€•Á¥Í½‘•9Õµ‰•ÉÌèÙ…±Õ”¹•Á¥Í½‘•9Õµ‰•ÉÌ°(€€€€€€€€€€€•Ù¥‘•¹”èÙ…±Õ”¹•Ù¥‘•¹”°(€€€€€€€€€€€É•Á…¥É%¹ÍÑÉÕÑ¥½¸èÙ…±Õ”¹É•Á…¥É%¹ÍÑÉÕÑ¥½¸°(€€€€€€€€€€€É•Í½±Ù•è™…±Í”(€€€€€€€€¤(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹ŒÉ•¹…µ•¡|Ù…±Õ”èMÑÉ¥¹œ°|¡…É…Ñ•ÉÌèm¡…É…Ñ•ÉAÉ½™¥±•t¤€´øMÑÉ¥¹œì(€€€€€€€¡…É…Ñ•ÉáÑÉ…Ñ½È¹…ÁÁ±åI•¹…µ•Ì¡Ù…±Õ”°¡…É…Ñ•ÉÌè¡…É…Ñ•ÉÌ¤(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹Œ©Í½¸ñPè¹½‘…‰±”ø¡|Ù…±Õ”èP¤€´øMÑÉ¥¹œì(€€€€€€€Õ…É(€€€€€€€€€€€±•Ð‘…Ñ„€ôÑÉäü)M=9¹½‘•È¹ÍÉ¥ÁÑ½É”¹•¹½‘”¡Ù…±Õ”¤°(€€€€€€€€€€€±•ÐÑ•áÐ€ôMÑÉ¥¹œ¡‘…Ñ„è‘…Ñ„°•¹½‘¥¹œè€¹ÕÑ˜à¤(€€€€€€€•±Í”ìÉ•ÑÕÉ¸€‰íôˆô(€€€€€€€É•ÑÕÉ¸Ñ•áÐ(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÍåÍÑ•µ	…Í”€ô€ˆˆˆ(€€€ƒ’öƒšb¿’â·–n÷ž®[–Æ?–ú»ž~·–&Ÿ–Þ—’âk–2[šRçžò[žÎïžî’â·žj’â’â«–>_¦fC¢*ž
çŽ’â—š‚ó¢¾ï–>[’â+šâã¢Ö’êŸ¾ò3–>«¢úO–ë–öO–&4M¡•µ„ƒ¢ššÆžjšVÃš6»¾òo’â7¢úO–ë–"šzC¢þž¢/¾ò3’â7¢fkšz–:šZ¢¾š6»¾ò3’â7šN¢«šRç–B7Ž–òëšžî«–þ¦†ï–â›šv—’êëž&§¦'š.§–J3–B;šzs¾ò3¦ÿ–7šrëšŠÃžú{¢úÇŽ¦7–’7¦–¦k–J3–>«šRûž.ƒ¢¾w’â7¢†3–*£Ž(€€€€ˆˆˆ((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÍÑÉ¥¹ÉÉ…äèmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°(€€€€€€€€‰¥Ñ•µÌˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•Ð¹…µ¥¹M¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°(€€€€€€€€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰É•¹…µ•Ìˆèl(€€€€€€€€€€€€€€€€‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°(€€€€€€€€€€€€€€€€‰¥Ñ•µÌˆèl(€€€€€€€€€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°(€€€€€€€€€€€€€€€€€€€€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€€€€€€€€€€€€€‰Í½ÕÉ•9…µ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€€€€€€€€€‰Ñ…É•Ñ9…µ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€€€€t°(€€€€€€€€€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰Í½ÕÉ•9…µ”ˆ°€‰Ñ…É•Ñ9…µ”‰t°(€€€€€€€€€€€€€€€t°(€€€€€€€€€€€t°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰É•¹…µ•Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•Ð¡Õ¹­M¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°(€€€€€€€€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰ÍÕµµ…Éäˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰™…ÑÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€‰­•åÙ•¹ÑÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€‰•µ½Ñ¥½¹…±	•…ÑÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€‰ÁÉ½‘ÕÑ¥½¹9½Ñ•ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€‰•Ù¥‘•¹•¡…ÁÑ•É%ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰ÍÕµµ…Éäˆ°€‰™…ÑÌˆ°€‰­•åÙ•¹ÑÌˆ°€‰•µ½Ñ¥½¹…±	•…ÑÌˆ°€‰ÁÉ½‘ÕÑ¥½¹9½Ñ•Ìˆ°€‰•Ù¥‘•¹•¡…ÁÑ•É%Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•Ð…¹½¹¥…±¡…É…Ñ•ÉM¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰¥ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰Í½ÕÉ•9…µ•ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€‰ÍÉ¥ÁÑ9…µ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰É½±”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰É•±…Ñ¥½¹Í¡¥ÁÌˆèÍÑÉ¥¹ÉÉ…ä°€‰•Ù¥‘•¹•¡…ÁÑ•É%ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¥ˆ°€‰Í½ÕÉ•9…µ•Ìˆ°€‰ÍÉ¥ÁÑ9…µ”ˆ°€‰É½±”ˆ°€‰É•±…Ñ¥½¹Í¡¥ÁÌˆ°€‰•Ù¥‘•¹•¡…ÁÑ•É%Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÝ½É±‘IÕ±•M¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰¥ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰ÍÕ‰©•Ðˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰™…Ðˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰…ÕÍ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰•Ù¥‘•¹•¡…ÁÑ•É%ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¥ˆ°€‰ÍÕ‰©•Ðˆ°€‰™…Ðˆ°€‰…ÕÍ”ˆ°€‰•Ù¥‘•¹•¡…ÁÑ•É%Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÁÉ½ÁQ¡É•…‘M¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰¥ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰¹…µ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰‘É…µ…Ñ¥Õ¹Ñ¥½¸ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰¥¹ÑÉ½‘Õ•‘Á¥Í½‘”ˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••È‰t°(€€€€€€€€€€€€‰Á…å½™™Á¥Í½‘”ˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••È‰t°€‰ÕÉÉ•¹ÑMÑ…Ñ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰•Ù¥‘•¹•¡…ÁÑ•É%ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¥ˆ°€‰¹…µ”ˆ°€‰‘É…µ…Ñ¥Õ¹Ñ¥½¸ˆ°€‰¥¹ÑÉ½‘Õ•‘Á¥Í½‘”ˆ°€‰Á…å½™™Á¥Í½‘”ˆ°€‰ÕÉÉ•¹ÑMÑ…Ñ”ˆ°€‰•Ù¥‘•¹•¡…ÁÑ•É%Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÑ¥µ•±¥¹•M¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰¥ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰½É‘•Èˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••È‰t°(€€€€€€€€€€€€‰±½…Ñ¥½¸ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰Ñ¥µ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰Á…ÉÑ¥¥Á…¹ÑÌˆèÍÑÉ¥¹ÉÉ…ä°€‰…ÕÍ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰•Ù•¹Ðˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰•™™•Ðˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰•Ù¥‘•¹•¡…ÁÑ•É%ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¥ˆ°€‰½É‘•Èˆ°€‰±½…Ñ¥½¸ˆ°€‰Ñ¥µ”ˆ°€‰Á…ÉÑ¥¥Á…¹ÑÌˆ°€‰…ÕÍ”ˆ°€‰•Ù•¹Ðˆ°€‰•™™•Ðˆ°€‰•Ù¥‘•¹•¡…ÁÑ•É%Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÍÑ½Éå	¥‰±•M¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰ÁÉ•µ¥Í”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰…¹½¹¥…±¡…É…Ñ•ÉÌˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰¥Ñ•µÌˆè…¹½¹¥…±¡…É…Ñ•ÉM¡•µ…t°(€€€€€€€€€€€€‰Ý½É±‘IÕ±•Ìˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰¥Ñ•µÌˆèÝ½É±‘IÕ±•M¡•µ…t°(€€€€€€€€€€€€‰ÁÉ½ÁQ¡É•…‘Ìˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰¥Ñ•µÌˆèÁÉ½ÁQ¡É•…‘M¡•µ…t°(€€€€€€€€€€€€‰Ñ¥µ•±¥¹”ˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰¥Ñ•µÌˆèÑ¥µ•±¥¹•M¡•µ…t°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰ÁÉ•µ¥Í”ˆ°€‰…¹½¹¥…±¡…É…Ñ•ÉÌˆ°€‰Ý½É±‘IÕ±•Ìˆ°€‰ÁÉ½ÁQ¡É•…‘Ìˆ°€‰Ñ¥µ•±¥¹”‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•Ð•Á¥Í½‘•½¹ÑÉ…ÑM¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰‘½µ¥¹…¹Ñ½¹™±¥Ðˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰¹•Ý%¹™½Éµ…Ñ¥½¸ˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€‰Ù¥ÍÕ…±!½½¬ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰ÑÉ…¹Í¥Ñ¥½¹É½µAÉ•Ù¥½ÕÌˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰…Ñ¥Ù•AÉ½ÁQ¡É•…‘ÌˆèÍÑÉ¥¹ÉÉ…ä°€‰•¹ÑÉåMÑ…Ñ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€‰•á¥ÑMÑ…Ñ”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰‘½µ¥¹…¹Ñ½¹™±¥Ðˆ°€‰¹•Ý%¹™½Éµ…Ñ¥½¸ˆ°€‰Ù¥ÍÕ…±!½½¬ˆ°€‰ÑÉ…¹Í¥Ñ¥½¹É½µAÉ•Ù¥½ÕÌˆ°€‰…Ñ¥Ù•AÉ½ÁQ¡É•…‘Ìˆ°€‰•¹ÑÉåMÑ…Ñ”ˆ°€‰•á¥ÑMÑ…Ñ”‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹Œ½ÕÑ±¥¹•M¡•µ„¡•Á¥Í½‘•½Õ¹Ðè%¹Ð°‘ÕÉ…Ñ¥½¹M•½¹‘Ìè%¹Ð¤€´ømMÑÉ¥¹œè¹åtì(€€€€€€€±•ÐÉ…¹”€ôÁ¥Í½‘•	Õ‘•Ð¹Í•¹•I…¹”¡‘ÕÉ…Ñ¥½¹M•½¹‘Ìè‘ÕÉ…Ñ¥½¹M•½¹‘Ì¤(€€€€€€€±•ÐÁ±…¸èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€€€€€‰¹Õµ‰•Èˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••È‰t°€‰Ñ¥Ñ±”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€‰Í½ÕÉ•¡…ÁÑ•É%ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€€€€€‰Á±…¹¹•‘M•¹•½Õ¹Ðˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••Èˆ°€‰µ¥¹¥µÕ´ˆèÉ…¹”¹±½Ý•É	½Õ¹°€‰µ…á¥µÕ´ˆèÉ…¹”¹ÕÁÁ•É	½Õ¹‘t°(€€€€€€€€€€€€€€€€‰½Á•¹¥¹!½½¬ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰½‰©•Ñ¥Ù”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€‰É•Ù•ÉÍ…°ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰•¹‘!½½¬ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€‰½¹ÑÉ…Ðˆè•Á¥Í½‘•½¹ÑÉ…ÑM¡•µ„°(€€€€€€€€€€€t°(€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¹Õµ‰•Èˆ°€‰Ñ¥Ñ±”ˆ°€‰Í½ÕÉ•¡…ÁÑ•É%Ìˆ°€‰Á±…¹¹•‘M•¹•½Õ¹Ðˆ°€‰½Á•¹¥¹!½½¬ˆ°€‰½‰©•Ñ¥Ù”ˆ°€‰É•Ù•ÉÍ…°ˆ°€‰•¹‘!½½¬ˆ°€‰½¹ÑÉ…Ð‰t°(€€€€€€€t(€€€€€€€É•ÑÕÉ¸l(€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€€€€€‰±½±¥¹”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰•¹É”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€‰Ñ¡•µ•ÌˆèÍÑÉ¥¹ÉÉ…ä°€‰Í½ÕÉ•…ÑÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€€€€€€€€€€‰•Á¥Í½‘•Ìˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰µ¥¹%Ñ•µÌˆè•Á¥Í½‘•½Õ¹Ð°€‰µ…á%Ñ•µÌˆè•Á¥Í½‘•½Õ¹Ð°€‰¥Ñ•µÌˆèÁ±…¹t°(€€€€€€€€€€€t°(€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰±½±¥¹”ˆ°€‰•¹É”ˆ°€‰Ñ¡•µ•Ìˆ°€‰Í½ÕÉ•…ÑÌˆ°€‰•Á¥Í½‘•Ì‰t°(€€€€€€€t(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹Œ•Á¥Í½‘•M¡•µ„¡‘ÕÉ…Ñ¥½¹M•½¹‘Ìè%¹Ð¤€´ømMÑÉ¥¹œè¹åtì(€€€€€€€±•ÐÉ…¹”€ôÁ¥Í½‘•	Õ‘•Ð¹Í•¹•I…¹”¡‘ÕÉ…Ñ¥½¹M•½¹‘Ìè‘ÕÉ…Ñ¥½¹M•½¹‘Ì¤(€€€€€€€±•Ð‘¥…±½Õ”èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl‰ÍÁ•…­•Èˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰Ñ•áÐˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰ut°(€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰ÍÁ•…­•Èˆ°€‰Ñ•áÐ‰t°(€€€€€€€t(€€€€€€€±•ÐÍ•¹”èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€€€€€‰¡•…‘¥¹œˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰±½…Ñ¥½¸ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€‰…Ñ¥½¸ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€‰‘¥…±½Õ”ˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰¥Ñ•µÌˆè‘¥…±½Õ•t°(€€€€€€€€€€€t°(€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¡•…‘¥¹œˆ°€‰±½…Ñ¥½¸ˆ°€‰…Ñ¥½¸ˆ°€‰‘¥…±½Õ”‰t°(€€€€€€€t(€€€€€€€É•ÑÕÉ¸l(€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€€€€€‰Í•¹•Ìˆèl(€€€€€€€€€€€€€€€€€€€€‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰µ¥¹%Ñ•µÌˆèÉ…¹”¹±½Ý•É	½Õ¹°(€€€€€€€€€€€€€€€€€€€€‰µ…á%Ñ•µÌˆèÉ…¹”¹ÕÁÁ•É	½Õ¹°€‰¥Ñ•µÌˆèÍ•¹”°(€€€€€€€€€€€€€€€t°(€€€€€€€€€€€t°(€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰Í•¹•Ì‰t°(€€€€€€€t(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÍ•µ…¹Ñ¥Õ‘¥ÑM¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰Í½É”ˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••Èˆ°€‰µ¥¹¥µÕ´ˆè€À°€‰µ…á¥µÕ´ˆè€ÄÀÁt°(€€€€€€€€€€€€‰Á…ÍÍ•ˆèl‰ÑåÁ”ˆè€‰‰½½±•…¸‰t°€‰¥ÍÍÕ•ÌˆèÍÑÉ¥¹ÉÉ…ä°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰Í½É”ˆ°€‰Á…ÍÍ•ˆ°€‰¥ÍÍÕ•Ì‰t°(€€€t((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ±•ÐÍ•É¥•ÍÕ‘¥ÑM¡•µ„èmMÑÉ¥¹œè¹åt€ôl(€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€‰¥ÍÍÕ•Ìˆèl(€€€€€€€€€€€€€€€€‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°(€€€€€€€€€€€€€€€€‰¥Ñ•µÌˆèl(€€€€€€€€€€€€€€€€€€€€‰ÑåÁ”ˆè€‰½‰©•Ðˆ°€‰…‘‘¥Ñ¥½¹…±AÉ½Á•ÉÑ¥•Ìˆè™…±Í”°(€€€€€€€€€€€€€€€€€€€€‰ÁÉ½Á•ÉÑ¥•Ìˆèl(€€€€€€€€€€€€€€€€€€€€€€€€‰Í•Ù•É¥Ñäˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œˆ°€‰•¹Õ´ˆèl‰‰±½­•Èˆ°€‰µ…©½Èˆ°€‰µ¥¹½È‰ut°(€€€€€€€€€€€€€€€€€€€€€€€€‰…Ñ•½Éäˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œˆ°€‰•¹Õ´ˆèl‰Í½ÕÉ•¥‘•±¥Ñäˆ°€‰½¹Ñ¥¹Õ¥Ñäˆ°€‰¡…É…Ñ•Èˆ°€‰Á…¥¹œˆ°€‰¡½½¬ˆ°€‰‘¥…±½Õ”ˆ°€‰ÁÉ½‘ÕÑ¥½¸ˆ°€‰½µÁ±¥…¹”‰ut°(€€€€€€€€€€€€€€€€€€€€€€€€‰•Á¥Í½‘•9Õµ‰•ÉÌˆèl‰ÑåÁ”ˆè€‰…ÉÉ…äˆ°€‰¥Ñ•µÌˆèl‰ÑåÁ”ˆè€‰¥¹Ñ••È‰ut°(€€€€€€€€€€€€€€€€€€€€€€€€‰•Ù¥‘•¹”ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°€‰É•Á…¥É%¹ÍÑÉÕÑ¥½¸ˆèl‰ÑåÁ”ˆè€‰ÍÑÉ¥¹œ‰t°(€€€€€€€€€€€€€€€€€€€t°(€€€€€€€€€€€€€€€€€€€€‰É•ÅÕ¥É•ˆèl‰Í•Ù•É¥Ñäˆ°€‰…Ñ•½Éäˆ°€‰•Á¥Í½‘•9Õµ‰•ÉÌˆ°€‰•Ù¥‘•¹”ˆ°€‰É•Á…¥É%¹ÍÑÉÕÑ¥½¸‰t°(€€€€€€€€€€€€€€€t°(€€€€€€€€€€€t°(€€€€€€€t°(€€€€€€€€‰É•ÅÕ¥É•ˆèl‰¥ÍÍÕ•Ì‰t°(€€€t)ô