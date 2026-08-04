import Foundation

enum BookAnalysisPipeline {
    private struct EvidenceDigest: Codable, Sendable {
        let summary: String
        let events: [String]
        let characters: [String]
        let hooks: [String]
        let foreshadowing: [String]
        let styleSignals: [String]
        let evidenceChapterIDs: [String]
    }

    private struct SectionDTO: Codable, Sendable {
        let id: String
        let title: String
        let markdown: String
        let evidenceChapterIDs: [String]
    }

    private struct SectionsResponse: Codable, Sendable {
        let sections: [SectionDTO]
    }

    private struct MetaResponse: Codable, Sendable {
        let logline: String
        let summary: String
        let genreTags: [String]
        let targetReader: String
    }

    static func runOffline(
        document: NovelDocument,
        characters: [CharacterProfile]
    ) -> BookAnalysisReport {
        let evidence = document.chapters.prefix(12).map { "[\($0.id)] \(summary($0.content))" }
        let cast = characters.prefix(8).map { "- \($0.targetName)：\($0.role)，源文出现 \($0.occurrences) 次" }
        let sections = [
            BookAnalysisSection(
                id: "overview",
                title: "内容概览",
                markdown: "共 \(document.chapters.count) 章、\(document.characterCount) 个有效字符。\n\n" + evidence.joined(separator: "\n"),
                evidenceChapterIDs: document.chapters.prefix(12).map(\.id)
            ),
            BookAnalysisSection(
                id: "structure",
                title: "结构与节奏",
                markdown: "本地基础分析按章节边界识别叙事阶段。建议在线模式进一步判断开篇钩子、冲突升级、高潮区间和伏笔兑现。",
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
            BookAnalysisSection(
                id: "characters",
                title: "人物系统",
                markdown: cast.joined(separator: "\n"),
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
            BookAnalysisSection(
                id: "highlights",
                title: "商业爽点",
                markdown: "本地模式不冒充深度语义判断。可重点复核身份差、信息差、公开对抗、能力兑现和不可逆选择的分布。",
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
            BookAnalysisSection(
                id: "style",
                title: "语言与文风",
                markdown: "建议在线模式分析叙述视角、句长、对白比例、情绪控制和场景化能力。",
                evidenceChapterIDs: document.chapters.prefix(6).map(\.id)
            ),
            BookAnalysisSection(
                id: "learning",
                title: "技法与仿写",
                markdown: "先复用因果结构和信息释放节奏，不复制受版权保护的具体表达、人物或标志性桥段。",
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
        ]
        return BookAnalysisReport(
            title: document.title,
            logline: document.intro.isEmpty ? summary(document.rawText) : document.intro,
            summary: "离线基础报告已覆盖完整章节索引；接入双模型后可生成带证据的深度拆解。",
            genreTags: [],
            targetReader: "待在线分析",
            sections: sections,
            coveragePercent: 100,
            generatedAt: Date(),
            mode: .offline
        )
    }

    static func runOnline(
        document: NovelDocument,
        characters: [CharacterProfile],
        prompts: [PromptAsset],
        settings: ModelSettings,
        apiKey: String,
        progress: @escaping (String, Int, Int, Double) -> Void
    ) async throws -> BookAnalysisReport {
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let groups = evidenceGroups(document.chapters)
        var digests: [EvidenceDigest] = []
        for (index, group) in groups.enumerated() {
            try Task.checkCancellation()
            progress("正在抽取章节证据", index + 1, groups.count, Double(index + 1) / Double(groups.count) * 0.42)
            let digest: EvidenceDigest = try await client.structured(
                stage: .bookAnalysisExtract,
                instructions: baseInstruction(prompts) + "\n只抽取当前证据块，不做全书结论。",
                input: group.map { "[\($0.id)] \($0.title)\n\($0.content)" }.joined(separator: "\n\n"),
                name: "book_evidence_\(index + 1)",
                schema: evidenceSchema
            )
            let allowed = Set(group.map(\.id))
            digests.append(EvidenceDigest(
                summary: digest.summary,
                events: digest.events,
                characters: digest.characters,
                hooks: digest.hooks,
                foreshadowing: digest.foreshadowing,
                styleSignals: digest.styleSignals,
                evidenceChapterIDs: digest.evidenceChapterIDs.filter(allowed.contains)
            ))
        }

        if digests.count > 12 {
            progress("正在分层压缩长篇证据", groups.count, groups.count, 0.48)
            var compressed: [EvidenceDigest] = []
            for start in stride(from: 0, to: digests.count, by: 6) {
                let part = Array(digests[start..<min(start + 6, digests.count)])
                let digest: EvidenceDigest = try await client.structured(
                    stage: .bookAnalysisDigest,
                    instructions: baseInstruction(prompts) + "\n压缩重复信息但保留全部证据 ID、因果、伏笔和风格信号。",
                    input: json(part),
                    name: "book_digest_\(start / 6 + 1)",
                    schema: evidenceSchema
                )
                compressed.append(digest)
            }
            digests = compressed
        }

        progress("正在执行结构、人物与商业专项分析", groups.count, groups.count, 0.56)
        let finalDigests = digests
        async let metaCall: MetaResponse = client.structured(
            stage: .bookAnalysisStructure,
            instructions: baseInstruction(prompts) + "\n生成全书元信息，结论必须来自证据摘要。",
            input: json(finalDigests),
            name: "book_meta",
            schema: metaSchema
        )
        async let structureCall: SectionsResponse = specialty(
            ids: ["overview", "structure"],
            focus: "内容概览、开篇钩子、阶段划分、节奏密度、高潮低谷和伏笔兑现",
            stage: .bookAnalysisStructure,
            digests: finalDigests,
            prompts: prompts,
            client: client
        )
        async let characterCall: SectionsResponse = specialty(
            ids: ["characters"],
            focus: "主角目标与弧光、反派动机、配角功能、人物关系变化和角色使用效率",
            stage: .bookAnalysisCharacters,
            digests: finalDigests,
            prompts: prompts,
            client: client
        )
        async let commercialCall: SectionsResponse = specialty(
            ids: ["highlights", "style", "learning"],
            focus: "爽点机制与间隔、文风和对白、可复用创作技法、仿写方向与版权边界",
            stage: .bookAnalysisCommercial,
            digests: finalDigests,
            prompts: prompts,
            client: client
        )

        let (meta, structure, character, commercial) = try await (
            metaCall, structureCall, characterCall, commercialCall
        )
        progress("正在组装六模块报告并校验证据", groups.count, groups.count, 0.92)
        let sourceSections = structure.sections + character.sections + commercial.sections
        let allowedIDs = Set(document.chapters.map(\.id))
        let orderedIDs = ["overview", "structure", "characters", "highlights", "style", "learning"]
        let titles = [
            "overview": "内容概览", "structure": "结构与节奏", "characters": "人物系统",
            "highlights": "商业爽点", "style": "语言与文风", "learning": "技法与仿写",
        ]
        let sections = orderedIDs.map { id in
            let value = sourceSections.first(where: { $0.id == id })
            return BookAnalysisSection(
                id: id,
                title: titles[id] ?? value?.title ?? id,
                markdown: value?.markdown ?? "该模块模型输出缺失，请重新生成或人工补充。",
                evidenceChapterIDs: value?.evidenceChapterIDs.filter(allowedIDs.contains) ?? []
            )
        }
        return BookAnalysisReport(
            title: document.title,
            logline: meta.logline,
            summary: meta.summary,
            genreTags: meta.genreTags,
            targetReader: meta.targetReader,
            sections: sections,
            coveragePercent: Int(Double(Set(digests.flatMap(\.evidenceChapterIDs)).count) / Double(max(1, document.chapters.count)) * 100),
            generatedAt: Date(),
            mode: .online
        )
    }

    static func revise(
        report: BookAnalysisReport,
        instruction: String,
        prompts: [PromptAsset],
        settings: ModelSettings,
        apiKey: String
    ) async throws -> BookAnalysisReport {
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let response: SectionsResponse = try await client.structured(
            stage: .bookAnalysisRevision,
            instructions: baseInstruction(prompts) + "\n只按用户指令修订相关模块，不删除既有证据 ID，不虚构新证据。",
            input: "【当前报告】\(renderMarkdown(report))\n【修订指令】\(instruction)",
            name: "book_revision",
            schema: sectionsSchema(ids: report.sections.map(\.id))
        )
        let revisedSections = report.sections.map { original in
            guard let revised = response.sections.first(where: { $0.id == original.id }) else { return original }
            return BookAnalysisSection(
                id: original.id,
                title: original.title,
                markdown: revised.markdown,
                evidenceChapterIDs: revised.evidenceChapterIDs.isEmpty
                    ? original.evidenceChapterIDs
                    : revised.evidenceChapterIDs
            )
        }
        return BookAnalysisReport(
            title: report.title,
            logline: report.logline,
            summary: report.summary,
            genreTags: report.genreTags,
            targetReader: report.targetReader,
            sections: revisedSections,
            coveragePercent: report.coveragePercent,
            generatedAt: Date(),
            mode: .online
        )
    }

    static func renderMarkdown(_ report: BookAnalysisReport) -> String {
        var lines = [
            "# 《\(report.title)》拆书报告",
            "",
            "- 一句话梗概：\(report.logline)",
            "- 目标读者：\(report.targetReader)",
            "- 类型标签：\(report.genreTags.joined(separator: "、"))",
            "- 章节证据覆盖：\(report.coveragePercent)%",
            "",
            report.summary,
            "",
        ]
        for section in report.sections {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.markdown)
            lines.append("")
            lines.append("证据：\(section.evidenceChapterIDs.joined(separator: "、"))")
            lines.append("")
        }
        lines.append("> AI辅助分析，须结合原著版权、编辑判断与实际市场验证。")
        return lines.joined(separator: "\n")
    }

    private static func specialty(
        ids: [String],
        focus: String,
        stage: ModelStage,
        digests: [EvidenceDigest],
        prompts: [PromptAsset],
        client: LLMClient
    ) async throws -> SectionsResponse {
        try await client.structured(
            stage: stage,
            instructions: baseInstruction(prompts) + "\n专项任务：\(focus)。只输出指定模块：\(ids.joined(separator: "、"))。",
            input: json(digests),
            name: "book_\(ids.joined(separator: "_"))",
            schema: sectionsSchema(ids: ids)
        )
    }

    private static func evidenceGroups(_ chapters: [Chapter]) -> [[Chapter]] {
        let chapters = NovelParser.evidenceFragments(chapters: chapters)
        var groups: [[Chapter]] = []
        var current: [Chapter] = []
        var count = 0
        for chapter in chapters {
            if !current.isEmpty && count + chapter.characterCount > 12_000 {
                groups.append(current)
                current = []
                count = 0
            }
            current.append(chapter)
            count += chapter.characterCount
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func baseInstruction(_ prompts: [PromptAsset]) -> String {
        """
        你是中文网文拆书系统中的受限分析节点。只依据带章节 ID 的证据，区分原文事实、分析推论和创作建议；不输出思维过程。

        \(PromptAssets.mergedInstruction(["story-evidence", "book-analysis"], assets: prompts))
        """
    }

    private static func summary(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(compact.prefix(160))
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder.scriptForge.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]

    private static let evidenceSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "summary": ["type": "string"], "events": stringArray,
            "characters": stringArray, "hooks": stringArray,
            "foreshadowing": stringArray, "styleSignals": stringArray,
            "evidenceChapterIDs": stringArray,
        ],
        "required": ["summary", "events", "characters", "hooks", "foreshadowing", "styleSignals", "evidenceChapterIDs"],
    ]

    private static let metaSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "logline": ["type": "string"], "summary": ["type": "string"],
            "genreTags": stringArray, "targetReader": ["type": "string"],
        ],
        "required": ["logline", "summary", "genreTags", "targetReader"],
    ]

    private static func sectionsSchema(ids: [String]) -> [String: Any] {
        [
            "type": "object", "additionalProperties": false,
            "properties": [
                "sections": [
                    "type": "array", "minItems": ids.count, "maxItems": ids.count,
                    "items": [
                        "type": "object", "additionalProperties": false,
                        "properties": [
                            "id": ["type": "string", "enum": ids],
                            "title": ["type": "string"], "markdown": ["type": "string"],
                            "evidenceChapterIDs": stringArray,
                        ],
                        "required": ["id", "title", "markdown", "evidenceChapterIDs"],
                    ],
                ],
            ],
            "required": ["sections"],
        ]
    }
}
