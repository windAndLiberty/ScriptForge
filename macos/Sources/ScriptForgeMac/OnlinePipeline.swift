import Foundation

enum OnlinePipeline {
    struct ChunkAnalysis: Codable {
        let summary: String
        let facts: [String]
        let keyEvents: [String]
        let emotionalBeats: [String]
        let productionNotes: [String]
    }

    struct EpisodePlan: Codable {
        let number: Int
        let title: String
        let sourceChapterIds: [String]
        let openingHook: String
        let objective: String
        let reversal: String
        let endHook: String
    }

    struct Outline: Codable {
        let logline: String
        let genre: String
        let themes: [String]
        let sourceFacts: [String]
        let episodes: [EpisodePlan]
    }

    struct SceneDraft: Codable {
        let heading: String
        let location: String
        let action: String
        let dialogue: [DialogueLine]
    }

    struct EpisodeDraft: Codable {
        let scenes: [SceneDraft]
    }

    private static let baseInstructions = """
    你是中国微短剧总编剧。忠实保留原作因果、人物动机与核心设定，但必须重新组织为可拍摄的微短剧，不逐段缩写原文。
    3-5秒内建立处境或冲突；每集只推进一个主要目标；中段必须升级或反转；结尾用未完成行动、身份揭示或代价形成卡点。
    对白口语化且有潜台词，少用旁白解释；场景集中、道具可执行、动作可拍；爽点之后保留人物选择与情感后果。
    不得美化违法犯罪、歧视、拜金或低俗羞辱。不要复制长段原文。
    """

    static func run(
        document: NovelDocument,
        characters: [CharacterProfile],
        options: AdaptationOptions,
        settings: ModelSettings,
        apiKey: String,
        progress: @escaping (PipelinePhase, String, Double) -> Void
    ) async throws -> AdaptationResult {
        let client = OpenAIClient(settings: settings, apiKey: apiKey)
        let chapterGroups = stride(from: 0, to: document.chapters.count, by: 2).map {
            Array(document.chapters[$0..<min($0 + 2, document.chapters.count)])
        }
        var analyses: [ChunkAnalysis] = []
        for (index, group) in chapterGroups.enumerated() {
            progress(.analysis, "正在分析 \(min((index + 1) * 2, document.chapters.count)) / \(document.chapters.count) 章", 0.12 + Double(index + 1) / Double(chapterGroups.count) * 0.25)
            let input = group.map {
                "[\($0.id)｜第\($0.index)章 \($0.title)]\n\(String($0.content.prefix(16_000)))"
            }.joined(separator: "\n\n")
            let analysis: ChunkAnalysis = try await client.structured(
                instructions: baseInstructions + "\n当前阶段只抽取事实，不写剧本；每条事实必须能回溯到输入。",
                input: input,
                name: "chapter_analysis",
                schema: chunkSchema
            )
            analyses.append(analysis)
        }

        progress(.outline, "正在合并故事圣经并规划分集卡", 0.44)
        let renameMap = characters.map {
            "\($0.sourceName)→\($0.targetName)（\($0.role)；\($0.traits.joined(separator: "、"))）"
        }.joined(separator: "\n")
        let analysisData = try JSONEncoder().encode(analyses)
        let analysisJSON = String(data: analysisData, encoding: .utf8) ?? "[]"
        let outline: Outline = try await client.structured(
            instructions: baseInstructions + """

            必须严格使用人物改名表中的新名，输出中不得出现旧名。
            生成恰好 \(options.episodeCount) 集；单集目标 \(options.durationSeconds) 秒、\(options.scenesPerEpisode) 场；题材策略为“\(options.trendPreset.rawValue)”。
            """,
            input: """
            【作品】\(document.title)
            【人物改名表】
            \(renameMap)
            【分章分析】
            \(analysisJSON)
            请输出全局故事定位和分集卡。
            """,
            name: "episode_outline",
            schema: outlineSchema(episodeCount: options.episodeCount)
        )

        var episodes: [Episode] = []
        for (index, plan) in outline.episodes.prefix(options.episodeCount).enumerated() {
            progress(.drafting, "正在生成第 \(index + 1) / \(options.episodeCount) 集", 0.56 + Double(index) / Double(options.episodeCount) * 0.33)
            let source = document.chapters.filter {
                plan.sourceChapterIds.contains($0.id)
            }.map {
                "[\($0.id)]\n\(String($0.content.prefix(12_000)))"
            }.joined(separator: "\n")
            let continuity = episodes.last.map {
                "上一集卡点：\($0.endHook)\n上一场：\($0.scenes.last?.action ?? "")"
            } ?? "首集"
            let draft: EpisodeDraft = try await client.structured(
                instructions: baseInstructions + """

                只使用以下人物新名：\(characters.map(\.targetName).joined(separator: "、"))。
                写恰好 \(options.scenesPerEpisode) 场。每场包含场次时空、地点、可拍动作和至少3句对白。不得出现旧名。
                """,
                input: """
                【全局故事】\(outline.logline)
                【本集分集卡】\(json(plan))
                【上一集连续性】\(continuity)
                【对应原文】\(source)
                """,
                name: "episode_\(plan.number)",
                schema: episodeSchema(sceneCount: options.scenesPerEpisode)
            )
            let scenes = draft.scenes.enumerated().map { sceneIndex, scene in
                ScriptScene(
                    id: "episode-\(plan.number)-scene-\(sceneIndex + 1)",
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
                sourceChapterIDs: plan.sourceChapterIds,
                openingHook: renamed(plan.openingHook, characters),
                objective: renamed(plan.objective, characters),
                reversal: renamed(plan.reversal, characters),
                endHook: renamed(plan.endHook, characters),
                scenes: scenes,
                content: ""
            )
            episode.content = OfflinePipeline.render(episode)
            episodes.append(episode)
        }

        progress(.quality, "正在执行确定性质量校验", 0.93)
        let report = QualityEvaluator.evaluate(
            episodes: episodes,
            characters: characters,
            options: options
        )
        return AdaptationResult(
            logline: renamed(outline.logline, characters),
            genre: outline.genre,
            themes: outline.themes,
            sourceFacts: outline.sourceFacts.map { renamed($0, characters) },
            episodes: episodes,
            quality: report,
            generatedAt: Date(),
            mode: .online
        )
    }

    private static func renamed(_ value: String, _ characters: [CharacterProfile]) -> String {
        CharacterExtractor.applyRenames(value, characters: characters)
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static let stringArray: [String: Any] = [
        "type": "array",
        "items": ["type": "string"],
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
        ],
        "required": ["summary", "facts", "keyEvents", "emotionalBeats", "productionNotes"],
    ]

    private static func outlineSchema(episodeCount: Int) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "logline": ["type": "string"],
                "genre": ["type": "string"],
                "themes": stringArray,
                "sourceFacts": stringArray,
                "episodes": [
                    "type": "array",
                    "minItems": episodeCount,
                    "maxItems": episodeCount,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "number": ["type": "integer"],
                            "title": ["type": "string"],
                            "sourceChapterIds": stringArray,
                            "openingHook": ["type": "string"],
                            "objective": ["type": "string"],
                            "reversal": ["type": "string"],
                            "endHook": ["type": "string"],
                        ],
                        "required": [
                            "number", "title", "sourceChapterIds", "openingHook",
                            "objective", "reversal", "endHook",
                        ],
                    ],
                ],
            ],
            "required": ["logline", "genre", "themes", "sourceFacts", "episodes"],
        ]
    }

    private static func episodeSchema(sceneCount: Int) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "scenes": [
                    "type": "array",
                    "minItems": sceneCount,
                    "maxItems": sceneCount,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "heading": ["type": "string"],
                            "location": ["type": "string"],
                            "action": ["type": "string"],
                            "dialogue": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "additionalProperties": false,
                                    "properties": [
                                        "speaker": ["type": "string"],
                                        "text": ["type": "string"],
                                    ],
                                    "required": ["speaker", "text"],
                                ],
                            ],
                        ],
                        "required": ["heading", "location", "action", "dialogue"],
                    ],
                ],
            ],
            "required": ["scenes"],
        ]
    }
}
