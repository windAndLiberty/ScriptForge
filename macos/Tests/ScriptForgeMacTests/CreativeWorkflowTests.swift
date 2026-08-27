import XCTest
@testable import ScriptForgeMac

private struct FakeCreativeModelClient: CreativeWorkflowModelClient {
    func generate(_ request: CreativeWorkflowRequest) async throws -> CreativeGenerationPayload {
        let items = (1...request.batchCount).map { index in
            CreativeGenerationPayload.Item(
                kind: request.workflowID == .continuityAudit ? "warning" : "chapter",
                name: "条目 \(index)",
                summary: "摘要 \(index)",
                content: "正文 \(index)",
                details: ["目标 \(index)", "冲突 \(index)", "信息 \(index)", "钩子 \(index)", "节拍 \(index)"]
            )
        }
        return CreativeGenerationPayload(
            title: request.workflowID.title,
            summary: "结构化结果",
            markdown: "# \(request.workflowID.title)",
            items: items
        )
    }
}

final class CreativeWorkflowTests: XCTestCase {
    func testRegistryContainsSixAuthorWorkflows() {
        XCTAssertEqual(CreativeWorkflowRegistry.definitions.count, 6)
        XCTAssertEqual(Set(CreativeWorkflowRegistry.definitions.map(\.id)), Set(CreativeWorkflowID.allCases))
    }

    func testWorkflowWaitsForBYOKAndResumesFromModelStep() async throws {
        let input = WorkflowRunInput(seed: "失忆剑客回乡", batchCount: 1)
        let run = WorkflowEngine.start(workflowID: .incubation, input: input)
        let prompt = try compiled(.incubation, seed: input.seed)

        let offline = await WorkflowEngine.advance(run: run, prompt: prompt, modelClient: nil)

        XCTAssertEqual(offline.run.status, .waitingForModel)
        XCTAssertEqual(offline.run.steps[0].status, .completed)
        XCTAssertEqual(offline.run.steps[1].status, .waiting)

        let resumed = WorkflowEngine.resume(offline.run)
        let online = await WorkflowEngine.advance(
            run: resumed,
            prompt: prompt,
            modelClient: FakeCreativeModelClient()
        )

        XCTAssertEqual(online.run.status, .waitingForApproval)
        XCTAssertEqual(online.generated.count, 1)
        XCTAssertEqual(online.run.steps[1].status, .completed)
    }

    func testThreeChapterProductionHasOneCardApprovalThenDraftApproval() async throws {
        var input = WorkflowRunInput(seed: "", batchCount: 3)
        input.selectedChapterIDs = [UUID(), UUID(), UUID()]
        var run = WorkflowEngine.start(workflowID: .chapterProduction, input: input)
        let prompt = try compiled(.chapterProduction, seed: "")

        let cards = await WorkflowEngine.advance(
            run: run,
            prompt: prompt,
            modelClient: FakeCreativeModelClient()
        )
        XCTAssertEqual(cards.run.status, .waitingForApproval)
        XCTAssertEqual(cards.run.steps[cards.run.activeStepIndex].id, "approve-cards")
        XCTAssertEqual(cards.generated.first?.payload.items.count, 3)

        run = try WorkflowEngine.approve(cards.run)
        let drafts = await WorkflowEngine.advance(
            run: run,
            prompt: prompt,
            modelClient: FakeCreativeModelClient()
        )
        XCTAssertEqual(drafts.run.status, .waitingForApproval)
        XCTAssertEqual(drafts.run.steps[drafts.run.activeStepIndex].id, "approve-drafts")
        XCTAssertEqual(drafts.generated.first?.payload.items.count, 3)
    }

    func testEveryTemplateCanReachAnApprovalWithFakeModel() async throws {
        for workflowID in CreativeWorkflowID.allCases where workflowID != .chapterProduction {
            var input = WorkflowRunInput(seed: "测试灵感", batchCount: 1)
            if workflowID == .outline { input.parameters["chapterCount"] = "2" }
            let prompt = try compiled(workflowID, seed: input.seed)
            let result = await WorkflowEngine.advance(
                run: WorkflowEngine.start(workflowID: workflowID, input: input),
                prompt: prompt,
                modelClient: FakeCreativeModelClient()
            )
            XCTAssertEqual(result.run.status, .waitingForApproval, "\(workflowID)")
        }
    }

    func testPromptLayersAndContextExclusionAreDeterministic() throws {
        let revision = CreativePromptRevision(id: UUID(), instruction: "工作流偏好", createdAt: Date())
        let override = CreativePromptOverride(
            workflowID: .chapterPolish,
            instruction: revision.instruction,
            revisions: [revision],
            updatedAt: Date()
        )
        let prompt = try CreativePromptCompiler.compile(
            workflowID: .chapterPolish,
            workflowOverride: override,
            projectInstruction: "项目规则",
            runInstruction: "本次要求",
            variables: ["seed": "原始输入"],
            context: [
                (id: "keep", label: "保留资料", content: "可见"),
                (id: "hide", label: "隐藏资料", content: "不可见"),
            ],
            excludedContextIDs: ["hide"]
        )

        XCTAssertTrue(prompt.instructions.contains("工作流偏好"))
        XCTAssertTrue(prompt.instructions.contains("项目规则"))
        XCTAssertTrue(prompt.instructions.contains("本次要求"))
        XCTAssertLessThan(try XCTUnwrap(prompt.instructions.range(of: "工作流偏好")?.lowerBound),
                          try XCTUnwrap(prompt.instructions.range(of: "项目规则")?.lowerBound))
        XCTAssertTrue(prompt.input.contains("保留资料"))
        XCTAssertFalse(prompt.input.contains("隐藏资料"))
        XCTAssertEqual(prompt.snapshot.contextLabels, ["保留资料"])
    }

    func testStructuralValidatorStopsMissingBatchItems() {
        let payload = CreativeGenerationPayload(
            title: "规划",
            summary: "摘要",
            markdown: "内容",
            items: [CreativeGenerationPayload.Item(
                kind: "chapter",
                name: "第一章",
                summary: "摘要",
                content: "正文",
                details: []
            )]
        )
        XCTAssertFalse(CreativeWorkflowValidator.validate(
            payload,
            workflowID: .outline,
            requestedCount: 3
        ).isEmpty)
    }

    func testLegacyEditedPromptMigratesToWorkflowOverride() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgePrompts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CreativePromptRepository(baseURL: root)
        let legacy = PromptAsset(
            id: "episode-drafting",
            title: "旧提示词",
            scope: "",
            influence: "",
            instruction: "保留作者修改过的章节写作规则",
            isDefault: false,
            updatedAt: Date()
        )

        let migrated = repository.load(legacyAssets: [legacy])
        let chapterPrompt = try XCTUnwrap(migrated.first(where: { $0.workflowID == .chapterProduction }))

        XCTAssertEqual(chapterPrompt.instruction, legacy.instruction)
        XCTAssertEqual(chapterPrompt.revisions.last?.instruction, legacy.instruction)
        XCTAssertEqual(repository.load().first(where: { $0.workflowID == .chapterProduction })?.instruction,
                       legacy.instruction)
    }

    private func compiled(_ workflowID: CreativeWorkflowID, seed: String) throws -> CompiledCreativePrompt {
        try CreativePromptCompiler.compile(
            workflowID: workflowID,
            workflowOverride: nil,
            projectInstruction: "",
            runInstruction: "",
            variables: ["seed": seed],
            context: [],
            excludedContextIDs: []
        )
    }
}
