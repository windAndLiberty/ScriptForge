import Foundation

enum StoryboardPipeline {
    private struct ShotResponse: Codable, Sendable {
        let sceneID: String
        let title: String
        let durationSeconds: Double
        let shotSize: String
        let cameraMovement: String
        let composition: String
        let visualAction: String
        let dialogue: String
        let narration: String
        let soundEffects: String
        let imagePrompt: String
        let negativePrompt: String
        let continuityNotes: String
        let productionNotes: String
    }

    private struct EpisodeResponse: Codable, Sendable {
        let visualStyle: String
        let characterVisualAnchors: [String]
        let shots: [ShotResponse]
    }

    static func runOffline(
        result: AdaptationResult,
        characters: [CharacterProfile],
        durationSeconds: Int
    ) -> ProductionPackage {
        let episodes = result.episodes.map { episode in
            let episodeText = episode.content + "\n" + episode.scenes.map(\.action).joined(separator: "\n")
            let episodeAnchors = visualAnchors(characters, matching: episodeText)
            let candidates = episode.scenes.flatMap { scene -> [ShotResponse] in
                let sceneText = [
                    scene.heading,
                    scene.location,
                    scene.action,
                    scene.dialogue.map { $0.speaker + $0.text }.joined(separator: "\n"),
                ].joined(separator: "\n")
                let sceneAnchors = visualAnchors(characters, matching: sceneText)
                var shots = [ShotResponse(
                    sceneID: scene.id,
                    title: scene.heading,
                    durationSeconds: 4,
                    shotSize: "中景",
                    cameraMovement: "轻微推进",
                    composition: "竖屏主体居中，保留前后景层次",
                    visualAction: scene.action,
                    dialogue: "",
                    narration: "",
                    soundEffects: "环境底噪与动作同期声",
                    imagePrompt: imagePrompt(scene: scene, beat: scene.action, anchors: sceneAnchors),
                    negativePrompt: defaultNegativePrompt,
                    continuityNotes: "延续本场人物服装、道具位置与光线方向",
                    productionNotes: "优先使用可实拍动作和明确演员反应"
                )]
                for line in scene.dialogue {
                    shots.append(ShotResponse(
                        sceneID: scene.id,
                        title: line.speaker + "反应",
                        durationSeconds: 3,
                        shotSize: "近景",
                        cameraMovement: "固定或微推",
                        composition: "人物眼神位落在竖屏上三分线",
                        visualAction: line.speaker + "完成台词并给出清晰反应。",
                        dialogue: line.speaker + "：" + line.text,
                        narration: "",
                        soundEffects: "保留呼吸、衣料与现场同期声",
                        imagePrompt: imagePrompt(scene: scene, beat: line.speaker + "说：" + line.text, anchors: sceneAnchors),
                        negativePrompt: defaultNegativePrompt,
                        continuityNotes: "与上一镜保持视线、轴线和动作衔接",
                        productionNotes: "台词短促，反应先于切镜"
                    ))
                }
                return shots
            }
            let safeCandidates = candidates.isEmpty ? [fallbackShot(episode)] : candidates
            return makeEpisode(
                episode: episode,
                response: EpisodeResponse(
                    visualStyle: "现实质感的中国竖屏微短剧，电影化光影，人物表演优先",
                    characterVisualAnchors: episodeAnchors,
                    shots: safeCandidates
                ),
                durationSeconds: durationSeconds,
                fallbackAnchors: episodeAnchors
            )
        }
        return ProductionPackage(
            version: ProductionPackage.currentVersion,
            createdAt: Date(),
            mode: .offline,
            episodes: episodes
        )
    }

    static func runOnline(
        result: AdaptationResult,
        characters: [CharacterProfile],
        durationSeconds: Int,
        prompts: [PromptAsset],
        settings: ModelSettings,
        apiKey: String,
        interfaceLanguage: AppLanguage = .chinese,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> ProductionPackage {
        let client = LLMClient(settings: settings, apiKey: apiKey)
        var storyboards: [EpisodeStoryboard] = []
        for (index, episode) in result.episodes.enumerated() {
            try Task.checkCancellation()
            let episodeAnchors = visualAnchors(characters, matching: episode.content)
            progress(
                interfaceLanguage == .english
                    ? "Designing shots, sound, and continuity for EP \(episode.number)"
                    : "正在设计 EP \(episode.number) 的镜头、声音与连续性",
                Double(index) / Double(max(result.episodes.count, 1))
            )
            let response: EpisodeResponse = try await client.structured(
                stage: .storyboardPlanning,
                instructions: onlineInstruction(prompts: prompts),
                input: """
                [Fixed Format] 9:16 vertical frame; target duration: \(durationSeconds) seconds.
                [Stable Character Visual Anchors]
                \(episodeAnchors.joined(separator: "\n"))
                [Episode Contract] Objective: \(episode.objective); reversal: \(episode.reversal); ending: \(episode.endHook)
                [Approved Screenplay]
                \(episode.content)
                """,
                name: "episode_\(episode.number)_storyboard",
                schema: episodeSchema
            )
            storyboards.append(makeEpisode(
                episode: episode,
                response: response,
                durationSeconds: durationSeconds,
                fallbackAnchors: episodeAnchors
            ))
        }
        progress(interfaceLanguage == .english ? "Storyboard package complete" : "分镜制作包已完成", 1)
        return ProductionPackage(
            version: ProductionPackage.currentVersion,
            createdAt: Date(),
            mode: .online,
            episodes: storyboards
        )
    }

    static func renderMarkdown(_ package: ProductionPackage, projectName: String) -> String {
        var lines = [
            "# 《\(projectName)》分镜制作包",
            "",
            "- 版本：\(package.version)",
            "- 模式：\(package.mode.rawValue)",
            "- 总镜数：\(package.shotCount)",
            "- 提示：AI 辅助分镜须经导演、摄影、美术、录音与制片复核。",
            "",
        ]
        for episode in package.episodes {
            lines.append("## EP \(episode.episodeNumber) · \(episode.title)")
            lines.append("")
            lines.append("规格：\(episode.aspectRatio) · \(episode.visualStyle) · \(String(format: "%.1f", episode.totalDurationSeconds)) 秒")
            lines.append("")
            lines.append("人物视觉锚点：")
            lines.append(contentsOf: episode.characterVisualAnchors.map { "- \($0)" })
            lines.append("")
            for shot in episode.shots {
                lines.append("### \(shot.number). \(shot.title)（\(String(format: "%.1f", shot.durationSeconds))s）")
                lines.append("")
                lines.append("- 景别/运动：\(shot.shotSize) · \(shot.cameraMovement)")
                lines.append("- 构图：\(shot.composition)")
                lines.append("- 画面动作：\(shot.visualAction)")
                if !shot.dialogue.isEmpty { lines.append("- 台词：\(shot.dialogue)") }
                if !shot.narration.isEmpty { lines.append("- 旁白：\(shot.narration)") }
                lines.append("- 声音：\(shot.soundEffects)")
                lines.append("- 连续性：\(shot.continuityNotes)")
                lines.append("- 制作备注：\(shot.productionNotes)")
                lines.append("- 首帧提示词：\(shot.imagePrompt)")
                lines.append("- 反向提示词：\(shot.negativePrompt)")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func makeEpisode(
        episode: Episode,
        response: EpisodeResponse,
        durationSeconds: Int,
        fallbackAnchors: [String]
    ) -> EpisodeStoryboard {
        let usable = response.shots.filter { !$0.visualAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let source = usable.isEmpty ? [fallbackShot(episode)] : usable
        let durations = normalizedDurations(source.map(\.durationSeconds), target: Double(durationSeconds))
        let allowedSceneIDs = Set(episode.scenes.map(\.id))
        let shots = source.enumerated().map { index, value in
            StoryboardShot(
                id: "ep\(episode.number)-shot-\(index + 1)",
                number: index + 1,
                sceneID: allowedSceneIDs.contains(value.sceneID) ? value.sceneID : (episode.scenes.first?.id ?? "scene-1"),
                title: clean(value.title, fallback: "镜头 \(index + 1)"),
                durationSeconds: durations[index],
                shotSize: clean(value.shotSize, fallback: "中景"),
                cameraMovement: clean(value.cameraMovement, fallback: "固定"),
                composition: clean(value.composition, fallback: "9:16 竖屏主体构图"),
                visualAction: value.visualAction.trimmingCharacters(in: .whitespacesAndNewlines),
                dialogue: value.dialogue.trimmingCharacters(in: .whitespacesAndNewlines),
                narration: value.narration.trimmingCharacters(in: .whitespacesAndNewlines),
                soundEffects: clean(value.soundEffects, fallback: "现场同期声"),
                imagePrompt: clean(value.imagePrompt, fallback: value.visualAction),
                negativePrompt: clean(value.negativePrompt, fallback: defaultNegativePrompt),
                continuityNotes: clean(value.continuityNotes, fallback: "保持人物造型、道具与轴线连续"),
                productionNotes: clean(value.productionNotes, fallback: "导演现场复核"),
                keyframePath: nil,
                narrationPath: nil
            )
        }
        return EpisodeStoryboard(
            episodeNumber: episode.number,
            title: episode.title,
            aspectRatio: "9:16",
            visualStyle: clean(response.visualStyle, fallback: "现实质感竖屏微短剧"),
            characterVisualAnchors: response.characterVisualAnchors.isEmpty ? fallbackAnchors : response.characterVisualAnchors,
            shots: shots
        )
    }

    private static func visualAnchors(
        _ characters: [CharacterProfile],
        matching text: String
    ) -> [String] {
        let matched = characters.filter { character in
            text.contains(character.targetName) || text.contains(character.sourceName)
        }
        let selected = matched.isEmpty ? Array(characters.prefix(6)) : Array(matched.prefix(12))
        return selected.map { character in
            let traits = character.traits.prefix(4).joined(separator: ", ")
            let identity = traits.isEmpty ? "maintain a consistent appearance appropriate to the story role" : traits
            return "\(character.targetName): role=\(character.role); stable identifying traits=\(identity); keep facial structure, hairstyle, and primary costume colors consistent across every shot."
        }
    }

    static func onlineInstruction(prompts: [PromptAsset]) -> String {
        """
        You are a storyboard director and line producer for Chinese vertical micro-drama. Convert only the approved screenplay into shots. Do not add characters, events, settings, or outcomes. Write production-facing natural-language fields in Simplified Chinese, but write imagePrompt and negativePrompt in English for broad image-model compatibility.

        \(PromptAssets.mergedInstruction(["storyboard-production"], assets: prompts))
        """
    }

    static func imagePrompt(scene: ScriptScene, beat: String, anchors: [String]) -> String {
        "Opening keyframe for a Chinese vertical micro-drama, 9:16, location: \(scene.location), action beat: \(beat), cinematic realistic lighting, clear facial expressions, \(anchors.joined(separator: "; "))"
    }

    private static func fallbackShot(_ episode: Episode) -> ShotResponse {
        ShotResponse(
            sceneID: episode.scenes.first?.id ?? "scene-1",
            title: episode.title,
            durationSeconds: 1,
            shotSize: "中景",
            cameraMovement: "固定",
            composition: "9:16 竖屏主体构图",
            visualAction: episode.openingHook,
            dialogue: "",
            narration: "",
            soundEffects: "现场同期声",
            imagePrompt: "Chinese vertical micro-drama, 9:16, \(episode.openingHook), cinematic realistic lighting, clear facial expressions",
            negativePrompt: defaultNegativePrompt,
            continuityNotes: "保持人物和道具连续",
            productionNotes: "导演现场复核"
        )
    }

    private static func normalizedDurations(_ values: [Double], target: Double) -> [Double] {
        guard !values.isEmpty, target > 0 else { return [] }
        let positive = values.map { max(0.5, min($0, 15)) }
        let targetHalfSeconds = Int((target * 2).rounded())
        if targetHalfSeconds < positive.count {
            let equal = target / Double(positive.count)
            var result = Array(repeating: equal, count: positive.count)
            result[result.count - 1] += target - result.reduce(0, +)
            return result
        }

        let sum = positive.reduce(0, +)
        let distributable = targetHalfSeconds - positive.count
        let idealExtras = positive.map { $0 / sum * Double(distributable) }
        var extras = idealExtras.map { Int(floor($0)) }
        var remainder = distributable - extras.reduce(0, +)
        let order = idealExtras.indices.sorted {
            let left = idealExtras[$0] - floor(idealExtras[$0])
            let right = idealExtras[$1] - floor(idealExtras[$1])
            return left == right ? $0 < $1 : left > right
        }
        var offset = 0
        while remainder > 0 {
            extras[order[offset % order.count]] += 1
            remainder -= 1
            offset += 1
        }
        return extras.map { Double($0 + 1) / 2 }
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static let defaultNegativePrompt = "landscape framing, text watermark, subtitles, logo, malformed fingers, extra limbs, distorted face, inconsistent character appearance, low resolution"

    private static let shotSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["sceneID", "title", "durationSeconds", "shotSize", "cameraMovement", "composition", "visualAction", "dialogue", "narration", "soundEffects", "imagePrompt", "negativePrompt", "continuityNotes", "productionNotes"],
        "properties": [
            "sceneID": ["type": "string"], "title": ["type": "string"],
            "durationSeconds": ["type": "number", "minimum": 0.5, "maximum": 15],
            "shotSize": ["type": "string"], "cameraMovement": ["type": "string"],
            "composition": ["type": "string"], "visualAction": ["type": "string"],
            "dialogue": ["type": "string"], "narration": ["type": "string"],
            "soundEffects": ["type": "string"], "imagePrompt": ["type": "string"],
            "negativePrompt": ["type": "string"], "continuityNotes": ["type": "string"],
            "productionNotes": ["type": "string"],
        ],
    ]

    private static let episodeSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["visualStyle", "characterVisualAnchors", "shots"],
        "properties": [
            "visualStyle": ["type": "string"],
            "characterVisualAnchors": ["type": "array", "items": ["type": "string"]],
            "shots": ["type": "array", "minItems": 1, "items": shotSchema],
        ],
    ]
}
