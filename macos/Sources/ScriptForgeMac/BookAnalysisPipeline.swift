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
        characters: [CharacterProfile],
        language: AppLanguage
    ) -> BookAnalysisReport {
        let evidence = document.chapters.prefix(12).map { "[\($0.id)] \(summary($0.content))" }
        let cast = characters.prefix(8).map { character in
            if language == .english {
                return "- \(character.targetName): \(englishRole(character.role)); appears \(character.occurrences) time(s) in the source"
            }
            return "- \(character.targetName)：\(character.role)，源文出现 \(character.occurrences) 次"
        }
        let sectionIDs = ["overview", "structure", "characters", "highlights", "style", "learning"]
        let englishTitles = [
            "Content Overview", "Structure and Pacing", "Character System",
            "Commercial Highlights", "Language and Style", "Reusable Techniques",
        ]
        let chineseTitles = ["内容概览", "结构与节奏", "人物系统", "商业爽点", "语言与文风", "技法与仿写"]
        let titles = language == .english ? englishTitles : chineseTitles
        let markdown: [String]
        if language == .english {
            markdown = [
                "The source contains \(document.chapters.count) chapter(s) and \(document.characterCount) effective character(s).\n\n" + evidence.joined(separator: "\n"),
                "The local baseline identifies narrative stages from chapter boundaries. Online mode can further evaluate the opening hook, conflict escalation, climax range, and foreshadowing payoffs.",
                cast.isEmpty ? "No recurring character candidates were identified by the local extractor." : cast.joined(separator: "\n"),
                "Local mode does not pretend to perform deep semantic judgment. Review the distribution of status gaps, information gaps, public confrontations, ability payoffs, and irreversible choices.",
                "Use online mode to analyze point of view, sentence length, dialogue ratio, emotional control, and scene construction.",
                "Reuse causal structure and the pacing of information release; do not copy copyrighted wording, characters, or signature plot sequences.",
            ]
        } else {
            markdown = [
                "共 \(document.chapters.count) 章、\(document.characterCount) 个有效字符。\n\n" + evidence.joined(separator: "\n"),
                "本地基础分析按章节边界识别叙事阶段。建议在线模式进一步判断开篇钩子、冲突升级、高潮区间和伏笔兑现。",
                cast.joined(separator: "\n"),
                "本地模式不冒充深度语义判断。可重点复核身份差、信息差、公开对抗、能力兑现和不可逆选择的分布。",
                "建议在线模式分析叙述视角、句长、对白比例、情绪控制和场景化能力。",
                "先复用因果结构和信息释放节奏，不复制受版权保护的具体表达、人物或标志性桥段。",
            ]
        }
        let sections = [
            BookAnalysisSection(
                id: sectionIDs[0],
                title: titles[0],
                markdown: markdown[0],
                evidenceChapterIDs: document.chapters.prefix(12).map(\.id)
            ),
            BookAnalysisSection(
                id: sectionIDs[1],
                title: titles[1],
                markdown: markdown[1],
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
            BookAnalysisSection(
                id: sectionIDs[2],
                title: titles[2],
                markdown: markdown[2],
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
            BookAnalysisSection(
                id: sectionIDs[3],
                title: titles[3],
                markdown: markdown[3],
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
            BookAnalysisSection(
                id: sectionIDs[4],
                title: titles[4],
                markdown: markdown[4],
                evidenceChapterIDs: document.chapters.prefix(6).map(\.id)
            ),
            BookAnalysisSection(
                id: sectionIDs[5],
                title: titles[5],
                markdown: markdown[5],
                evidenceChapterIDs: document.chapters.map(\.id)
            ),
        ]
        return BookAnalysisReport(
            title: document.title,
            outputLanguage: language,
            logline: document.intro.isEmpty ? summary(document.rawText) : document.intro,
            summary: language == .english
                ? "This offline baseline covers the complete chapter index. Connect BYOK models for a deeper evidence-grounded analysis."
                : "离线基础报告已覆盖完整章节索引；接入双模型后可生成带证据的深度拆解。",
            genreTags: [],
            targetReader: language == .english ? "Pending online analysis" : "待在线分析",
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
        language: AppLanguage,
        progress: @escaping (String, Int, Int, Double) -> Void
    ) async throws -> BookAnalysisReport {
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let groups = evidenceGroups(document.chapters)
        var digests: [EvidenceDigest] = []
        for (index, group) in groups.enumerated() {
            try Task.checkCancellation()
            progress(localized("正在抽取章节证据", "Extracting chapter evidence", language), index + 1, groups.count, Double(index + 1) / Double(groups.count) * 0.42)
            let digest: EvidenceDigest = try await client.structured(
                stage: .bookAnalysisExtract,
                instructions: baseInstruction(prompts, language: language) +
                    "\nExtract only the current evidence block; do not draw whole-book conclusions. Keep the summary under 250 words and each evidence array concise. Prefer the strongest distinct items instead of restating the source.",
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
            progress(localized("正在分层压缩长篇证据", "Compressing long-form evidence hierarchically", language), groups.count, groups.count, 0.48)
            var compressed: [EvidenceDigest] = []
            for start in stride(from: 0, to: digests.count, by: 6) {
                let part = Array(digests[start..<min(start + 6, digests.count)])
                let digest: EvidenceDigest = try await client.structured(
                    stage: .bookAnalysisDigest,
                    instructions: baseInstruction(prompts, language: language) +
                        "\nCompress repeated information while preserving every evidence ID, causal link, foreshadowing item, and style signal. Merge duplicates and keep the summary under 300 words.",
                    input: json(part),
                    name: "book_digest_\(start / 6 + 1)",
                    schema: evidenceSchema
                )
                compressed.append(digest)
            }
            digests = compressed
        }

        progress(localized("正在执行结构、人物与商业专项分析", "Analyzing structure, characters, and commercial elements", language), groups.count, groups.count, 0.56)
        let finalDigests = digests
        async let metaCall: MetaResponse = client.structured(
            stage: .bookAnalysisStructure,
            instructions: baseInstruction(prompts, language: language) +
                "\nGenerate whole-book metadata. Every conclusion must come from the evidence digests.",
            input: json(finalDigests),
            name: "book_meta",
            schema: metaSchema
        )
        async let structureCall: SectionsResponse = specialty(
            ids: ["overview", "structure"],
            focus: "content overview, opening hook, narrative stages, pacing density, peaks and valleys, and foreshadowing payoffs",
            stage: .bookAnalysisStructure,
            digests: finalDigests,
            prompts: prompts,
            language: language,
            client: client
        )
        async let characterCall: SectionsResponse = specialty(
            ids: ["characters"],
            focus: "protagonist goals and arc, antagonist motivation, supporting-character functions, relationship changes, and character efficiency",
            stage: .bookAnalysisCharacters,
            digests: finalDigests,
            prompts: prompts,
            language: language,
            client: client
        )
        async let commercialCall: SectionsResponse = specialty(
            ids: ["highlights", "style", "learning"],
            focus: "payoff mechanisms and spacing, prose style and dialogue, reusable techniques, adaptation directions, and copyright boundaries",
            stage: .bookAnalysisCommercial,
            digests: finalDigests,
            prompts: prompts,
            language: language,
            client: client
        )

        let (meta, structure, character, commercial) = try await (
            metaCall, structureCall, characterCall, commercialCall
        )
        progress(localized("正在组装六模块报告并校验证据", "Assembling the six-section report and validating evidence", language), groups.count, groups.count, 0.92)
        let sourceSections = structure.sections + character.sections + commercial.sections
        let allowedIDs = Set(document.chapters.map(\.id))
        let orderedIDs = ["overview", "structure", "characters", "highlights", "style", "learning"]
        let titles = language == .english
            ? [
                "overview": "Content Overview", "structure": "Structure and Pacing", "characters": "Character System",
                "highlights": "Commercial Highlights", "style": "Language and Style", "learning": "Reusable Techniques",
            ]
            : [
                "overview": "内容概览", "structure": "结构与节奏", "characters": "人物系统",
                "highlights": "商业爽点", "style": "语言与文风", "learning": "技法与仿写",
            ]
        let sections = orderedIDs.map { id in
            let value = sourceSections.first(where: { $0.id == id })
            return BookAnalysisSection(
                id: id,
                title: titles[id] ?? value?.title ?? id,
                markdown: value?.markdown ?? localized("该模块模型输出缺失，请重新生成或人工补充。", "The model omitted this section. Regenerate it or complete it manually.", language),
                evidenceChapterIDs: value?.evidenceChapterIDs.filter(allowedIDs.contains) ?? []
            )
        }
        return BookAnalysisReport(
            title: document.title,
            outputLanguage: language,
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
        apiKey: String,
        language: AppLanguage
    ) async throws -> BookAnalysisReport {
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let response: SectionsResponse = try await client.structured(
            stage: .bookAnalysisRevision,
            instructions: baseInstruction(prompts, language: language) +
                "\nRevise only the sections affected by the user's instruction. Do not remove existing evidence IDs or invent new evidence.",
            input: "[Current Report]\n\(renderMarkdown(report, language: language))\n[Revision Instruction]\n\(instruction)",
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
            outputLanguage: language,
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

    static func renderMarkdown(_ report: BookAnalysisReport, language: AppLanguage? = nil) -> String {
        let resolvedLanguage = language ?? report.outputLanguage ?? .chinese
        var lines: [String]
        if resolvedLanguage == .english {
            lines = [
                "# \(report.title) — Book Analysis Report",
                "",
                "- Logline: \(report.logline)",
                "- Target Reader: \(report.targetReader)",
                "- Genre Tags: \(report.genreTags.joined(separator: ", "))",
                "- Chapter Evidence Coverage: \(report.coveragePercent)%",
                "",
                report.summary,
                "",
            ]
        } else {
            lines = [
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
        }
        for section in report.sections {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.markdown)
            lines.append("")
            lines.append(resolvedLanguage == .english
                ? "Evidence: \(section.evidenceChapterIDs.joined(separator: ", "))"
                : "证据：\(section.evidenceChapterIDs.joined(separator: "、"))")
            lines.append("")
        }
        lines.append(resolvedLanguage == .english
            ? "> AI-assisted analysis. Verify it against source rights, editorial judgment, and real market evidence."
            : "> AI辅助分析，须结合原著版权、编辑判断与实际市场验证。")
        return lines.joined(separator: "\n")
    }

    private static func specialty(
        ids: [String],
        focus: String,
        stage: ModelStage,
        digests: [EvidenceDigest],
        prompts: [PromptAsset],
        language: AppLanguage,
        client: LLMClient
    ) async throws -> SectionsResponse {
        try await client.structured(
            stage: stage,
            instructions: baseInstruction(prompts, language: language) +
                "\nSpecialized task: \(focus). Output only these section IDs: \(ids.joined(separator: ", ")). Keep each Markdown section focused and between 300 and 900 words; cite evidence IDs instead of copying long source passages.",
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

    static func baseInstruction(_ prompts: [PromptAsset], language: AppLanguage) -> String {
        let sharedPrompts = PromptAssets.mergedInstruction(["story-evidence", "book-analysis"], assets: prompts)
        let outputLanguage = language == .english ? "English" : "Simplified Chinese"
        return """
        You are a constrained fiction-analysis node. Use only evidence carrying chapter IDs. Clearly distinguish source facts, analytical inferences, and writing recommendations. Do not output hidden reasoning.

        \(sharedPrompts)

        OUTPUT LANGUAGE CONTRACT: Write every natural-language output value in \(outputLanguage), including summaries, labels, section titles, observations, and recommendations. Preserve proper names, verbatim source excerpts, and evidence IDs in their original form. This final language contract overrides any language preference in earlier prompt assets, but does not override evidence, privacy, or schema constraints.
        """
    }

    private static func localized(_ chinese: String, _ english: String, _ language: AppLanguage) -> String {
        language == .english ? english : chinese
    }

    private static func englishRole(_ role: String) -> String {
        switch role {
        case "核心主角", "主角", "男主", "女主": "Protagonist"
        case "主要角色": "Main character"
        case "关键配角", "配角", "盟友": "Supporting character"
        case "原稿核心人物": "Central source character"
        case "原稿人物": "Source character"
        default: "Character"
        }
    }

    private static func summary(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(compact.prefix(160))
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder.scriptForge.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func stringArray(maxItems: Int) -> [String: Any] {
        [
            "type": "array",
            "maxItems": maxItems,
            "items": ["type": "string"],
        ]
    }

    private static let evidenceSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "summary": ["type": "string"],
            "events": stringArray(maxItems: 16),
            "characters": stringArray(maxItems: 16),
            "hooks": stringArray(maxItems: 10),
            "foreshadowing": stringArray(maxItems: 12),
            "styleSignals": stringArray(maxItems: 10),
            "evidenceChapterIDs": stringArray(maxItems: 96),
        ],
        "required": ["summary", "events", "characters", "hooks", "foreshadowing", "styleSignals", "evidenceChapterIDs"],
    ]

    private static let metaSchema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "properties": [
            "logline": ["type": "string"],
            "summary": ["type": "string"],
            "genreTags": stringArray(maxItems: 12),
            "targetReader": ["type": "string"],
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
                            "title": ["type": "string"],
                            "markdown": ["type": "string"],
                            "evidenceChapterIDs": stringArray(maxItems: 96),
                        ],
                        "required": ["id", "title", "markdown", "evidenceChapterIDs"],
                    ],
                ],
            ],
            "required": ["sections"],
        ]
    }
}
