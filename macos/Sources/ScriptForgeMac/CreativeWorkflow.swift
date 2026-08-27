import Foundation

enum CreativeWorkflowError: LocalizedError {
    case unknownWorkflow
    case noActiveStep
    case approvalRequired
    case noCandidateArtifact
    case noSelectedChapter

    var errorDescription: String? {
        switch self {
        case .unknownWorkflow: "工作流不存在"
        case .noActiveStep: "工作流没有可执行步骤"
        case .approvalRequired: "请先确认当前候选结果"
        case .noCandidateArtifact: "没有可确认的候选结果"
        case .noSelectedChapter: "请先选择章节"
        }
    }
}

enum CreativeWorkflowRegistry {
    static let definitions: [WorkflowDefinition] = [
        definition(
            .incubation,
            summary: "把灵感整理成题材、卖点、主角与长期冲突明确的新书企划。",
            symbol: "sparkles",
            fields: [field("seed", "灵感或题材", "写下核心灵感、题材或一句话设想", true)],
            steps: [
                step("prepare", "整理创作目标", .local),
                step("generate", "生成新书企划", .model, route: .primary),
                step("approve", "确认企划", .approval),
            ]
        ),
        definition(
            .storyBible,
            summary: "建立人物、规则、地点、势力、物品与文风的长期事实库。",
            symbol: "books.vertical.fill",
            fields: [field("instruction", "补充要求", "需要重点维护的设定或禁忌", false)],
            steps: [
                step("collect", "选择相关资料", .local),
                step("generate", "构建故事圣经", .model, route: .primary),
                step("validate", "检查重复与空卡", .validation, optional: true),
                step("approve", "确认故事圣经", .approval),
            ]
        ),
        definition(
            .outline,
            summary: "从长期剧情弧拆出卷纲、章节目标、冲突、信息增量和钩子。",
            symbol: "list.bullet.rectangle.portrait.fill",
            fields: [field("chapterCount", "规划章节数", "1–200", true)],
            steps: [
                step("prepare", "整理企划与设定", .local),
                step("generate", "生成卷章规划", .model, route: .primary),
                step("validate", "检查章号、推进与钩子", .validation, optional: true),
                step("approve", "确认卷章规划", .approval),
            ]
        ),
        definition(
            .chapterProduction,
            summary: "批量确认章卡后逐章生成正文，并在每章成稿处停下。",
            symbol: "pencil.and.outline",
            fields: [field("batchCount", "本批章节数", "1–10", true)],
            steps: [
                step("context", "选择相关上下文", .local),
                step("chapter-cards", "生成本批章卡", .model, route: .primary),
                step("approve-cards", "确认本批章卡", .approval),
                step("draft", "逐章生成正文", .model, route: .primary),
                step("validate", "检查连续性与完整性", .validation, optional: true),
                step("approve-drafts", "逐章确认成稿", .approval),
            ]
        ),
        definition(
            .continuityAudit,
            summary: "检查人物状态、知情范围、时间、地点、能力、物品和伏笔。",
            symbol: "checkmark.shield.fill",
            fields: [field("scope", "审计范围", "选择章节或使用当前章节", false)],
            steps: [
                step("collect", "收集事实与章节", .local),
                step("audit", "执行连贯性审计", .model, route: .flash),
                step("validate", "归并重复问题", .validation, optional: true),
                step("approve", "确认问题台账", .approval),
            ]
        ),
        definition(
            .chapterPolish,
            summary: "在不改变剧情事实的前提下精修节奏、对白、视角和表达。",
            symbol: "wand.and.stars.inverse",
            fields: [field("instruction", "精修方向", "例如：压缩重复心理描写，增强对白攻守", false)],
            steps: [
                step("prepare", "读取当前正文与设定", .local),
                step("polish", "生成精修候选稿", .model, route: .primary),
                step("validate", "检查事实漂移", .validation, optional: true),
                step("approve", "对比并确认", .approval),
            ]
        ),
    ]

    static func definition(_ id: CreativeWorkflowID) -> WorkflowDefinition {
        definitions.first(where: { $0.id == id })!
    }

    private static func definition(
        _ id: CreativeWorkflowID,
        summary: String,
        symbol: String,
        fields: [WorkflowInputField],
        steps: [WorkflowStepDefinition]
    ) -> WorkflowDefinition {
        WorkflowDefinition(id: id, summary: summary, symbol: symbol, inputFields: fields, steps: steps)
    }

    private static func field(_ id: String, _ label: String, _ placeholder: String, _ required: Bool) -> WorkflowInputField {
        WorkflowInputField(id: id, label: label, placeholder: placeholder, required: required)
    }

    private static func step(
        _ id: String,
        _ title: String,
        _ kind: WorkflowStepKind,
        optional: Bool = false,
        route: ModelRoute? = nil
    ) -> WorkflowStepDefinition {
        WorkflowStepDefinition(id: id, title: title, kind: kind, isOptional: optional, modelRoute: route)
    }
}

struct CreativeWorkflowRequest: Sendable {
    let workflowID: CreativeWorkflowID
    let stepID: String
    let modelRoute: ModelRoute
    let batchCount: Int
    let prompt: CompiledCreativePrompt
}

protocol CreativeWorkflowModelClient: Sendable {
    func generate(_ request: CreativeWorkflowRequest) async throws -> CreativeGenerationPayload
}

struct BYOKCreativeWorkflowModelClient: CreativeWorkflowModelClient {
    let settings: ModelSettings
    let apiKey: String

    func generate(_ request: CreativeWorkflowRequest) async throws -> CreativeGenerationPayload {
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let countInstruction = request.batchCount > 1
            ? "Generate \(request.batchCount) independent, explicitly ordered items. The items array must contain exactly \(request.batchCount) entries."
            : "The items array must contain at least one actionable entry."
        let stepInstruction: String
        if request.workflowID == .chapterProduction && request.stepID == "draft" {
            stepInstruction = "Each item represents one complete chapter: name is the chapter title, summary is the chapter synopsis, and content is the full prose draft."
        } else if request.workflowID == .chapterProduction && request.stepID == "chapter-cards" {
            stepInstruction = "Each item represents one chapter card. In details, list the goal, conflict, new information, closing hook, and scene beats in that order."
        } else {
            stepInstruction = "Use items for independently editable cards or entries, and use markdown for the complete readable deliverable."
        }
        return try await client.structured(
            stage: stage(for: request.modelRoute),
            instructions: """
            \(request.prompt.instructions)

            \(countInstruction)
            \(stepInstruction)
            """,
            input: request.prompt.input,
            name: "creative_\(request.workflowID.rawValue)_\(request.stepID)",
            schema: Self.payloadSchema
        )
    }

    private func stage(for route: ModelRoute) -> ModelStage {
        route == .flash ? .creativeAudit : .creativeGeneration
    }

    private static let itemSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "name", "summary", "content", "details"],
        "properties": [
            "kind": ["type": "string"],
            "name": ["type": "string"],
            "summary": ["type": "string"],
            "content": ["type": "string"],
            "details": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    private static let payloadSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "summary", "markdown", "items"],
        "properties": [
            "title": ["type": "string"],
            "summary": ["type": "string"],
            "markdown": ["type": "string"],
            "items": ["type": "array", "items": itemSchema],
        ],
    ]
}

struct WorkflowAdvanceResult: Sendable {
    var run: WorkflowRun
    var generated: [(stepID: String, payload: CreativeGenerationPayload)]
}

enum WorkflowEngine {
    static func start(workflowID: CreativeWorkflowID, input: WorkflowRunInput) -> WorkflowRun {
        let definition = CreativeWorkflowRegistry.definition(workflowID)
        let now = Date()
        return WorkflowRun(
            id: UUID(),
            workflowID: workflowID,
            status: .queued,
            input: input,
            steps: definition.steps.map {
                WorkflowStepRun(
                    id: $0.id,
                    title: $0.title,
                    kind: $0.kind,
                    status: .pending,
                    artifactIDs: []
                )
            },
            activeStepIndex: 0,
            artifactIDs: [],
            promptSnapshotID: nil,
            modelNames: [:],
            endpointHost: nil,
            createdAt: now,
            updatedAt: now,
            errorMessage: nil
        )
    }

    static func advance(
        run original: WorkflowRun,
        prompt: CompiledCreativePrompt,
        modelClient: (any CreativeWorkflowModelClient)?
    ) async -> WorkflowAdvanceResult {
        var run = original
        var generated: [(String, CreativeGenerationPayload)] = []
        run.status = .running
        run.errorMessage = nil
        run.promptSnapshotID = prompt.snapshot.id

        while run.steps.indices.contains(run.activeStepIndex) {
            let index = run.activeStepIndex
            let definition = CreativeWorkflowRegistry.definition(run.workflowID).steps[index]
            if definition.isOptional && run.input.disabledStepIDs.contains(definition.id) {
                run.steps[index].status = .skipped
                run.steps[index].completedAt = Date()
                run.activeStepIndex += 1
                continue
            }
            switch definition.kind {
            case .local:
                run.steps[index].status = .running
                run.steps[index].startedAt = Date()
                run.steps[index].status = .completed
                run.steps[index].completedAt = Date()
                run.activeStepIndex += 1
            case .validation:
                run.steps[index].status = .running
                run.steps[index].startedAt = Date()
                if let payload = generated.last?.1 {
                    let problems = CreativeWorkflowValidator.validate(
                        payload,
                        workflowID: run.workflowID,
                        requestedCount: run.workflowID == .outline
                            ? Int(run.input.parameters["chapterCount"] ?? "")
                            : run.input.batchCount
                    )
                    if !problems.isEmpty {
                        let message = problems.joined(separator: "；")
                        run.steps[index].status = .failed
                        run.steps[index].errorMessage = message
                        run.status = .failed
                        run.errorMessage = message
                        run.updatedAt = Date()
                        return WorkflowAdvanceResult(run: run, generated: generated)
                    }
                }
                run.steps[index].status = .completed
                run.steps[index].completedAt = Date()
                run.activeStepIndex += 1
            case .approval:
                run.steps[index].status = .waiting
                run.status = .waitingForApproval
                run.updatedAt = Date()
                return WorkflowAdvanceResult(run: run, generated: generated)
            case .model:
                guard let modelClient else {
                    run.steps[index].status = .waiting
                    run.status = .waitingForModel
                    run.updatedAt = Date()
                    return WorkflowAdvanceResult(run: run, generated: generated)
                }
                run.steps[index].status = .running
                run.steps[index].startedAt = Date()
                do {
                    let requestedCount = run.workflowID == .outline
                        ? max(1, min(Int(run.input.parameters["chapterCount"] ?? "") ?? 1, 200))
                        : max(1, min(run.input.batchCount, 10))
                    let payload = try await modelClient.generate(CreativeWorkflowRequest(
                        workflowID: run.workflowID,
                        stepID: definition.id,
                        modelRoute: definition.modelRoute ?? .primary,
                        batchCount: requestedCount,
                        prompt: prompt
                    ))
                    generated.append((definition.id, payload))
                    run.steps[index].status = .completed
                    run.steps[index].completedAt = Date()
                    run.activeStepIndex += 1
                } catch {
                    run.steps[index].status = .failed
                    run.steps[index].errorMessage = error.localizedDescription
                    run.status = .failed
                    run.errorMessage = error.localizedDescription
                    run.updatedAt = Date()
                    return WorkflowAdvanceResult(run: run, generated: generated)
                }
            }
        }
        run.status = .completed
        run.updatedAt = Date()
        return WorkflowAdvanceResult(run: run, generated: generated)
    }

    static func approve(_ original: WorkflowRun) throws -> WorkflowRun {
        var run = original
        guard run.status == .waitingForApproval,
              run.steps.indices.contains(run.activeStepIndex),
              run.steps[run.activeStepIndex].kind == .approval else {
            throw CreativeWorkflowError.approvalRequired
        }
        run.steps[run.activeStepIndex].status = .completed
        run.steps[run.activeStepIndex].completedAt = Date()
        run.activeStepIndex += 1
        run.status = .queued
        run.updatedAt = Date()
        return run
    }

    static func resume(_ original: WorkflowRun) -> WorkflowRun {
        var run = original
        if run.steps.indices.contains(run.activeStepIndex),
           run.steps[run.activeStepIndex].status == .waiting {
            run.steps[run.activeStepIndex].status = .pending
        }
        if [.interrupted, .waitingForModel, .failed].contains(run.status) {
            run.status = .queued
            run.errorMessage = nil
        }
        if run.steps.indices.contains(run.activeStepIndex),
           run.steps[run.activeStepIndex].status == .failed {
            run.steps[run.activeStepIndex].status = .pending
            run.steps[run.activeStepIndex].errorMessage = nil
        }
        run.updatedAt = Date()
        return run
    }

    static func cancel(_ original: WorkflowRun) -> WorkflowRun {
        var run = original
        run.status = .cancelled
        run.updatedAt = Date()
        return run
    }

    static func regenerate(_ original: WorkflowRun) throws -> WorkflowRun {
        var run = original
        guard run.steps.indices.contains(run.activeStepIndex) else {
            throw CreativeWorkflowError.noActiveStep
        }
        let modelIndex = run.steps[..<run.activeStepIndex].lastIndex(where: { $0.kind == .model })
        guard let modelIndex else { throw CreativeWorkflowError.noActiveStep }
        for index in modelIndex..<run.steps.count {
            run.steps[index].status = .pending
            run.steps[index].startedAt = nil
            run.steps[index].completedAt = nil
            run.steps[index].errorMessage = nil
            if index == modelIndex { run.steps[index].artifactIDs = [] }
        }
        run.activeStepIndex = modelIndex
        run.status = .queued
        run.errorMessage = nil
        run.updatedAt = Date()
        return run
    }
}

enum CreativeWorkflowValidator {
    static func validate(
        _ payload: CreativeGenerationPayload,
        workflowID: CreativeWorkflowID,
        requestedCount: Int?
    ) -> [String] {
        var problems: [String] = []
        if payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("标题为空")
        }
        if payload.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("主内容为空")
        }
        if payload.items.isEmpty { problems.append("结构化条目为空") }
        if [.outline, .chapterProduction].contains(workflowID),
           let requestedCount, requestedCount > 0,
           payload.items.count != requestedCount {
            problems.append("请求 \(requestedCount) 项，实际返回 \(payload.items.count) 项")
        }
        let normalized = payload.items.map {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if normalized.count > 1 && Set(normalized).count != normalized.count {
            problems.append("存在完全重复的生成内容")
        }
        return problems
    }
}

enum CreativeContextBuilder {
    static func build(
        workspace: CreativeWorkspace,
        selectedChapterContents: [(id: UUID, title: String, content: String)]
    ) -> [(id: String, label: String, content: String)] {
        var result: [(String, String, String)] = []
        if let brief = workspace.activeBrief {
            result.append(("brief-\(brief.id)", "Approved Creative Brief", [
                brief.premise,
                "Protagonist: \(brief.protagonist)",
                "Central conflict: \(brief.centralConflict)",
                "Prose style: \(brief.tone)",
                "Constraints: \(brief.constraints.joined(separator: "; "))",
            ].joined(separator: "\n")))
        }
        if let bible = workspace.activeStoryBible {
            let visible = bible.cards.filter { $0.visibility == .included }
            let content = visible.map { card in
                "[\(card.kind.rawValue)] \(card.name): \(card.summary)"
            }.joined(separator: "\n")
            result.append(("bible-\(bible.id)", "Relevant Story Bible", content))
        }
        if let outline = workspace.activeOutline {
            let content = outline.chapterCards.map { card in
                "Chapter \(card.number), \(card.title): objective=\(card.objective); conflict=\(card.conflict); new information=\(card.reveal); hook=\(card.hook); beats=\(card.sceneBeats.joined(separator: " / "))"
            }.joined(separator: "\n")
            result.append(("outline-\(outline.id)", "Current Volume and Chapter Outline", content))
        }
        if !workspace.foreshadowing.isEmpty {
            let active = workspace.foreshadowing.filter { $0.status == .active || $0.status == .planned }
            result.append(("active-threads", "Active Foreshadowing", active.map {
                "\($0.name): \($0.notes)"
            }.joined(separator: "\n")))
        }
        if !workspace.characterStates.isEmpty {
            result.append(("character-states", "Current Character States", workspace.characterStates.map {
                "\($0.characterName): location=\($0.location); condition=\($0.condition); knowledge=\($0.knowledge.joined(separator: ", "))"
            }.joined(separator: "\n")))
        }
        for chapter in selectedChapterContents.suffix(3) {
            result.append(("chapter-\(chapter.id)", chapter.title, chapter.content))
        }
        return result.filter { !$0.2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
