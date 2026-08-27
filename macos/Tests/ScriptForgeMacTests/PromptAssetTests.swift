import Foundation
import XCTest
@testable import ScriptForgeMac

final class PromptAssetTests: XCTestCase {
    func testEveryBundledDefaultPromptIsEnglishOnly() throws {
        let adaptationText = PromptAssets.defaults.flatMap {
            [$0.title, $0.scope, $0.influence, $0.instruction]
        }.joined(separator: "\n")
        let creativeText = ([CreativePromptTemplates.systemContract] +
            CreativeWorkflowID.allCases.map(CreativePromptTemplates.defaultInstruction(for:)))
            .joined(separator: "\n")

        XCTAssertFalse(containsHan(adaptationText))
        XCTAssertFalse(containsHan(creativeText))
        XCTAssertEqual(PromptAssets.defaults.count, 8)
        XCTAssertEqual(CreativePromptTemplates.defaults.count, 6)
    }

    func testAdaptationDefaultsMigrateToEnglishWhileUserEditsRemainUntouched() throws {
        let root = temporaryDirectory("PromptAssetMigration")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PromptAssetRepository(baseURL: root)
        let oldDefault = PromptAsset(
            id: "story-evidence",
            title: "旧中文默认标题",
            scope: "旧范围",
            influence: "旧说明",
            instruction: "只抽取原文明确支持的事实。每条事实必须保留章节证据 ID；区分已发生事件、人物动机、世界规则和未兑现伏笔，不补写原文没有的信息。",
            isDefault: false,
            updatedAt: Date()
        )
        let customInstruction = "用户可以保留任意语言的自定义提示词。"
        let edited = PromptAsset(
            id: "book-analysis",
            title: "旧中文标题",
            scope: "旧范围",
            influence: "旧说明",
            instruction: customInstruction,
            isDefault: false,
            updatedAt: Date()
        )
        try repository.save([oldDefault, edited])

        let loaded = repository.load()
        let evidence = try XCTUnwrap(loaded.first { $0.id == "story-evidence" })
        let analysis = try XCTUnwrap(loaded.first { $0.id == "book-analysis" })

        XCTAssertEqual(evidence, PromptAssets.defaults.first { $0.id == "story-evidence" })
        XCTAssertEqual(analysis.title, "Six-Section Book Analysis")
        XCTAssertEqual(analysis.instruction, customInstruction)
        XCTAssertFalse(analysis.isDefault)
    }

    func testCreativeDefaultsMigrateToEnglishWhileCustomPromptRemainsUntouched() throws {
        let root = temporaryDirectory("CreativePromptMigration")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CreativePromptRepository(baseURL: root)
        let oldDefault = CreativePromptOverride(
            workflowID: .incubation,
            instruction: "将零散灵感整理成可执行的新书企划。明确题材、目标读者、核心卖点、主角欲望、中央冲突、长期升级空间与创作禁区。避免空泛口号，每个卖点都要能落到剧情行为。",
            revisions: [CreativePromptRevision(
                id: UUID(),
                instruction: "将零散灵感整理成可执行的新书企划。明确题材、目标读者、核心卖点、主角欲望、中央冲突、长期升级空间与创作禁区。避免空泛口号，每个卖点都要能落到剧情行为。",
                createdAt: Date()
            )],
            updatedAt: Date()
        )
        let customInstruction = "作者自定义内容可以使用任意语言。"
        let edited = CreativePromptOverride(
            workflowID: .chapterPolish,
            instruction: customInstruction,
            revisions: [CreativePromptRevision(id: UUID(), instruction: customInstruction, createdAt: Date())],
            updatedAt: Date()
        )
        try repository.save([oldDefault, edited])

        let loaded = repository.load()
        let incubation = try XCTUnwrap(loaded.first { $0.workflowID == .incubation })
        let polish = try XCTUnwrap(loaded.first { $0.workflowID == .chapterPolish })

        XCTAssertEqual(incubation.instruction, CreativePromptTemplates.defaultInstruction(for: .incubation))
        XCTAssertFalse(containsHan(incubation.instruction))
        XCTAssertEqual(polish.instruction, customInstruction)
    }

    func testCompiledDefaultPromptUsesEnglishScaffolding() throws {
        let prompt = try CreativePromptCompiler.compile(
            workflowID: .outline,
            workflowOverride: nil,
            projectInstruction: "",
            runInstruction: "",
            variables: ["seed": "A city that forgets one resident every winter."],
            context: [],
            excludedContextIDs: []
        )

        XCTAssertTrue(prompt.instructions.contains("[Workflow Instructions]"))
        XCTAssertTrue(prompt.input.contains("[Run Input]"))
        XCTAssertFalse(containsHan(prompt.instructions))
    }

    func testPipelinePromptScaffoldingAndImageDefaultsAreEnglishOnly() {
        var options = AdaptationOptions()
        options.durationSeconds = 60
        let character = CharacterProfile(
            id: "character-1",
            sourceName: "Original Name",
            targetName: "Locked Name",
            role: "Protagonist",
            traits: ["observant"],
            occurrences: 3,
            locked: true,
            nameSource: .manual
        )
        let scene = ScriptScene(
            id: "scene-1",
            heading: "Interior - Archive - Night",
            location: "Archive",
            action: "The protagonist opens a sealed ledger.",
            dialogue: []
        )
        let builtInText = [
            OnlinePipeline.systemBase,
            OnlinePipeline.draftInstruction(
                options: options,
                characters: [character],
                prompts: PromptAssets.defaults,
                plannedSceneCount: 2
            ),
            BookAnalysisPipeline.baseInstruction(PromptAssets.defaults, language: .english),
            BookAnalysisPipeline.baseInstruction(PromptAssets.defaults, language: .chinese),
            StoryboardPipeline.onlineInstruction(prompts: PromptAssets.defaults),
            StoryboardPipeline.imagePrompt(
                scene: scene,
                beat: scene.action,
                anchors: ["Locked Name: consistent dark coat"]
            ),
            StoryboardPipeline.defaultNegativePrompt,
        ].joined(separator: "\n")

        XCTAssertFalse(containsHan(builtInText))
        XCTAssertTrue(builtInText.contains("Simplified Chinese"))
        XCTAssertTrue(builtInText.contains("OUTPUT LANGUAGE CONTRACT"))

        let englishDraft = OnlinePipeline.draftInstruction(
            options: options,
            characters: [character],
            prompts: PromptAssets.defaults,
            plannedSceneCount: 2,
            outputLanguage: .english
        )
        XCTAssertTrue(englishDraft.contains("105–165 English dialogue words"))
        XCTAssertTrue(englishDraft.contains("exclusively in English"))
        XCTAssertFalse(containsHan(englishDraft))
    }

    private func containsHan(_ value: String) -> Bool {
        value.range(of: #"[\u3400-\u4DBF\u4E00-\u9FFF]"#, options: .regularExpression) != nil
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }
}
