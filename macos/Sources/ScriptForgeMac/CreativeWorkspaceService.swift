import Foundation

enum CreativeWorkspaceService {
    static func artifactKind(workflowID: CreativeWorkflowID, stepID: String) -> CreativeArtifactKind {
        switch (workflowID, stepID) {
        case (.incubation, _): .brief
        case (.storyBible, _): .storyBible
        case (.outline, _): .outline
        case (.chapterProduction, "chapter-cards"): .chapterCards
        case (.chapterProduction, _): .chapterDraft
        case (.continuityAudit, _): .auditReport
        case (.chapterPolish, _): .polishedChapter
        }
    }

    static func storePayload(
        _ payload: CreativeGenerationPayload,
        stepID: String,
        run: inout WorkflowRun,
        workspace: inout CreativeWorkspace,
        repository: ProjectRepository,
        projectID: UUID
    ) throws -> WorkflowArtifactReference {
        let artifactID = UUID()
        let path = try repository.writeCreativeArtifact(
            payload,
            artifactID: artifactID,
            projectID: projectID
        )
        let reference = WorkflowArtifactReference(
            id: artifactID,
            runID: run.id,
            workflowID: run.workflowID,
            kind: artifactKind(workflowID: run.workflowID, stepID: stepID),
            title: payload.title,
            summary: payload.summary,
            contentPath: path,
            isCandidate: true,
            createdAt: Date()
        )
        workspace.artifacts.append(reference)
        run.artifactIDs.append(artifactID)
        if let stepIndex = run.steps.firstIndex(where: { $0.id == stepID }) {
            run.steps[stepIndex].artifactIDs.append(artifactID)
        }
        if run.workflowID == .chapterProduction && stepID == "draft" {
            try createChapterCandidates(
                payload: payload,
                run: run,
                workspace: &workspace,
                repository: repository,
                projectID: projectID,
                source: .generated
            )
        }
        if run.workflowID == .chapterPolish && stepID == "polish" {
            try createChapterCandidates(
                payload: payload,
                run: run,
                workspace: &workspace,
                repository: repository,
                projectID: projectID,
                source: .polished
            )
        }
        return reference
    }

    static func storePromptSnapshot(
        _ snapshot: CreativePromptSnapshot,
        run: inout WorkflowRun,
        workspace: inout CreativeWorkspace,
        repository: ProjectRepository,
        projectID: UUID
    ) throws {
        guard !workspace.artifacts.contains(where: { $0.id == snapshot.id }) else { return }
        let path = try repository.writeCreativeArtifact(
            snapshot,
            artifactID: snapshot.id,
            projectID: projectID
        )
        workspace.artifacts.append(WorkflowArtifactReference(
            id: snapshot.id,
            runID: run.id,
            workflowID: run.workflowID,
            kind: .promptSnapshot,
            title: "提示词快照",
            summary: snapshot.contextLabels.joined(separator: "、"),
            contentPath: path,
            isCandidate: false,
            createdAt: snapshot.createdAt
        ))
        run.promptSnapshotID = snapshot.id
    }

    static func acceptCurrentArtifact(
        run: WorkflowRun,
        workspace: inout CreativeWorkspace,
        repository: ProjectRepository,
        projectID: UUID
    ) throws {
        let approvalID = run.steps.indices.contains(run.activeStepIndex)
            ? run.steps[run.activeStepIndex].id
            : ""
        if run.workflowID == .chapterProduction && approvalID == "approve-drafts" {
            return
        }
        if run.workflowID == .chapterPolish {
            return
        }
        let expectedKind: CreativeArtifactKind = {
            switch run.workflowID {
            case .incubation: .brief
            case .storyBible: .storyBible
            case .outline: .outline
            case .chapterProduction: .chapterCards
            case .continuityAudit: .auditReport
            case .chapterPolish: .polishedChapter
            }
        }()
        guard let index = workspace.artifacts.lastIndex(where: {
            $0.runID == run.id && $0.kind == expectedKind && $0.isCandidate
        }) else { throw CreativeWorkflowError.noCandidateArtifact }
        let reference = workspace.artifacts[index]
        let payload = try repository.readCreativeArtifact(
            CreativeGenerationPayload.self,
            relativePath: reference.contentPath,
            projectID: projectID
        )
        switch run.workflowID {
        case .incubation:
            let brief = makeBrief(payload: payload, input: run.input)
            workspace.briefs.append(brief)
            workspace.activeBriefID = brief.id
        case .storyBible:
            let bible = makeStoryBible(payload: payload)
            workspace.storyBibles.append(bible)
            workspace.activeStoryBibleID = bible.id
        case .outline:
            let outline = makeOutline(payload: payload, input: run.input, workspace: workspace)
            workspace.outlines.append(outline)
            mergePlannedChapters(outline.chapterCards, into: &workspace)
        case .chapterProduction:
            let cards = makeChapterCards(payload: payload, input: run.input, workspace: workspace)
            var outline = workspace.outlines.last ?? VolumeOutline(
                id: UUID(),
                number: 1,
                title: "第一卷",
                arcSummary: payload.summary,
                chapterCards: [],
                createdAt: Date()
            )
            for card in cards {
                if let existing = outline.chapterCards.firstIndex(where: { $0.number == card.number }) {
                    outline.chapterCards[existing] = card
                } else {
                    outline.chapterCards.append(card)
                }
            }
            outline.chapterCards.sort { $0.number < $1.number }
            if workspace.outlines.isEmpty { workspace.outlines.append(outline) }
            else { workspace.outlines[workspace.outlines.count - 1] = outline }
            mergePlannedChapters(cards, into: &workspace)
        case .continuityAudit:
            workspace.continuityIssues = makeContinuityIssues(payload)
        case .chapterPolish:
            break
        }
        workspace.artifacts[index].isCandidate = false
    }

    static func acceptChapterCandidate(
        chapterID: UUID,
        workspace: inout CreativeWorkspace
    ) throws {
        guard let chapterIndex = workspace.chapters.firstIndex(where: { $0.id == chapterID }),
              let candidateID = workspace.chapters[chapterIndex].candidateVersionID,
              let versionIndex = workspace.chapters[chapterIndex].versions.firstIndex(where: { $0.id == candidateID })
        else { throw CreativeWorkflowError.noCandidateArtifact }
        for index in workspace.chapters[chapterIndex].versions.indices {
            workspace.chapters[chapterIndex].versions[index].accepted = index == versionIndex
        }
        workspace.chapters[chapterIndex].currentVersionID = candidateID
        workspace.chapters[chapterIndex].candidateVersionID = nil
        workspace.chapters[chapterIndex].status = .accepted
    }

    static func rejectChapterCandidate(
        chapterID: UUID,
        workspace: inout CreativeWorkspace
    ) throws {
        guard let chapterIndex = workspace.chapters.firstIndex(where: { $0.id == chapterID }),
              workspace.chapters[chapterIndex].candidateVersionID != nil
        else { throw CreativeWorkflowError.noCandidateArtifact }
        workspace.chapters[chapterIndex].candidateVersionID = nil
        workspace.chapters[chapterIndex].status = workspace.chapters[chapterIndex].currentVersionID == nil
            ? .planned
            : .accepted
    }

    static func restoreVersion(
        chapterID: UUID,
        versionID: UUID,
        workspace: inout CreativeWorkspace,
        repository: ProjectRepository,
        projectID: UUID
    ) throws {
        guard let chapterIndex = workspace.chapters.firstIndex(where: { $0.id == chapterID }),
              let sourceVersion = workspace.chapters[chapterIndex].versions.first(where: { $0.id == versionID })
        else { throw CreativeWorkflowError.noCandidateArtifact }
        let content = try repository.readCreativeText(
            relativePath: sourceVersion.contentPath,
            projectID: projectID
        )
        let restoredID = UUID()
        let path = try repository.writeChapterVersion(
            content,
            chapterID: chapterID,
            versionID: restoredID,
            projectID: projectID
        )
        for index in workspace.chapters[chapterIndex].versions.indices {
            workspace.chapters[chapterIndex].versions[index].accepted = false
        }
        workspace.chapters[chapterIndex].versions.append(ChapterVersion(
            id: restoredID,
            createdAt: Date(),
            source: .restored,
            contentPath: path,
            summary: sourceVersion.summary,
            wordCount: wordCount(content),
            promptSnapshotID: sourceVersion.promptSnapshotID,
            accepted: true
        ))
        workspace.chapters[chapterIndex].currentVersionID = restoredID
        workspace.chapters[chapterIndex].candidateVersionID = nil
        workspace.chapters[chapterIndex].status = .accepted
    }

    static func saveManualChapter(
        chapterID: UUID,
        content: String,
        workspace: inout CreativeWorkspace,
        repository: ProjectRepository,
        projectID: UUID
    ) throws {
        guard let chapterIndex = workspace.chapters.firstIndex(where: { $0.id == chapterID }) else {
            throw CreativeWorkflowError.noSelectedChapter
        }
        let versionID = UUID()
        let path = try repository.writeChapterVersion(
            content,
            chapterID: chapterID,
            versionID: versionID,
            projectID: projectID
        )
        for index in workspace.chapters[chapterIndex].versions.indices {
            workspace.chapters[chapterIndex].versions[index].accepted = false
        }
        workspace.chapters[chapterIndex].versions.append(ChapterVersion(
            id: versionID,
            createdAt: Date(),
            source: .manual,
            contentPath: path,
            summary: String(content.prefix(120)),
            wordCount: wordCount(content),
            promptSnapshotID: nil,
            accepted: true
        ))
        workspace.chapters[chapterIndex].currentVersionID = versionID
        workspace.chapters[chapterIndex].candidateVersionID = nil
        workspace.chapters[chapterIndex].status = .accepted
    }

    private static func createChapterCandidates(
        payload: CreativeGenerationPayload,
        run: WorkflowRun,
        workspace: inout CreativeWorkspace,
        repository: ProjectRepository,
        projectID: UUID,
        source: ChapterVersionSource
    ) throws {
        let targetIDs: [UUID]
        if !run.input.selectedChapterIDs.isEmpty {
            targetIDs = Array(run.input.selectedChapterIDs.prefix(10))
        } else {
            targetIDs = workspace.chapters
                .filter { $0.status == .planned || $0.status == .accepted }
                .sorted { $0.number < $1.number }
                .prefix(max(1, min(run.input.batchCount, 10)))
                .map(\.id)
        }
        guard !targetIDs.isEmpty else { throw CreativeWorkflowError.noSelectedChapter }
        let usableItems = payload.items.isEmpty
            ? [CreativeGenerationPayload.Item(
                kind: "chapter",
                name: payload.title,
                summary: payload.summary,
                content: payload.markdown,
                details: []
            )]
            : payload.items
        for (offset, chapterID) in targetIDs.enumerated() {
            guard let chapterIndex = workspace.chapters.firstIndex(where: { $0.id == chapterID }) else { continue }
            let item = usableItems[min(offset, usableItems.count - 1)]
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? payload.markdown
                : item.content
            let versionID = UUID()
            let path = try repository.writeChapterVersion(
                content,
                chapterID: chapterID,
                versionID: versionID,
                projectID: projectID
            )
            workspace.chapters[chapterIndex].versions.append(ChapterVersion(
                id: versionID,
                createdAt: Date(),
                source: source,
                contentPath: path,
                summary: item.summary,
                wordCount: wordCount(content),
                promptSnapshotID: run.promptSnapshotID,
                accepted: false
            ))
            workspace.chapters[chapterIndex].candidateVersionID = versionID
            workspace.chapters[chapterIndex].status = .review
        }
    }

    private static func makeBrief(payload: CreativeGenerationPayload, input: WorkflowRunInput) -> CreativeBrief {
        let character = payload.items.first(where: { $0.kind.lowercased().contains("character") })
        return CreativeBrief(
            id: UUID(),
            title: payload.title,
            genre: input.parameters["genre"] ?? payload.items.first?.kind ?? "待确认",
            targetAudience: input.parameters["audience"] ?? "中文网文读者",
            premise: payload.summary,
            sellingPoints: payload.items.map(\.summary).filter { !$0.isEmpty },
            protagonist: character?.name ?? input.parameters["protagonist"] ?? "待作者确认",
            centralConflict: input.parameters["conflict"] ?? payload.items.first?.content ?? payload.summary,
            tone: input.parameters["tone"] ?? "由作者确认",
            constraints: payload.items.flatMap(\.details),
            createdAt: Date()
        )
    }

    private static func makeStoryBible(payload: CreativeGenerationPayload) -> CreativeStoryBible {
        CreativeStoryBible(
            id: UUID(),
            title: payload.title,
            cards: payload.items.map { item in
                StoryBibleCard(
                    id: UUID(),
                    kind: bibleKind(item.kind),
                    name: item.name,
                    summary: item.summary,
                    details: Dictionary(uniqueKeysWithValues: item.details.enumerated().map {
                        ("详情 \($0.offset + 1)", $0.element)
                    }),
                    aliases: [],
                    visibility: .included,
                    sourceChapterNumbers: []
                )
            },
            styleGuide: payload.markdown,
            forbiddenElements: [],
            createdAt: Date()
        )
    }

    private static func makeOutline(
        payload: CreativeGenerationPayload,
        input: WorkflowRunInput,
        workspace: CreativeWorkspace
    ) -> VolumeOutline {
        let requested = Int(input.parameters["chapterCount"] ?? "") ?? payload.items.count
        let cards = makeChapterCards(
            payload: payload,
            input: WorkflowRunInput(
                seed: input.seed,
                instruction: input.instruction,
                batchCount: max(1, requested),
                selectedChapterIDs: [],
                parameters: input.parameters,
                disabledStepIDs: input.disabledStepIDs,
                excludedContextIDs: input.excludedContextIDs
            ),
            workspace: workspace
        )
        return VolumeOutline(
            id: UUID(),
            number: workspace.outlines.count + 1,
            title: payload.title,
            arcSummary: payload.summary,
            chapterCards: cards,
            createdAt: Date()
        )
    }

    private static func makeChapterCards(
        payload: CreativeGenerationPayload,
        input: WorkflowRunInput,
        workspace: CreativeWorkspace
    ) -> [ChapterCard] {
        let nextNumber = (workspace.chapters.map(\.number).max() ?? 0) + 1
        let requested = max(1, input.batchCount)
        return payload.items.prefix(requested).enumerated().map { offset, item in
            let selectedChapter = input.selectedChapterIDs.indices.contains(offset)
                ? workspace.chapters.first(where: { $0.id == input.selectedChapterIDs[offset] })
                : nil
            let details = item.details + Array(repeating: "", count: max(0, 5 - item.details.count))
            return ChapterCard(
                id: UUID(),
                number: selectedChapter?.number ?? (nextNumber + offset),
                volumeNumber: selectedChapter?.volumeNumber ?? workspace.outlines.last?.number ?? 1,
                title: item.name,
                objective: details[0].isEmpty ? item.summary : details[0],
                conflict: details[1],
                reveal: details[2],
                hook: details[3],
                sceneBeats: Array(details.dropFirst(4)).filter { !$0.isEmpty },
                activeForeshadowingIDs: []
            )
        }
    }

    private static func mergePlannedChapters(_ cards: [ChapterCard], into workspace: inout CreativeWorkspace) {
        for card in cards {
            if let index = workspace.chapters.firstIndex(where: { $0.number == card.number }) {
                workspace.chapters[index].title = card.title
                workspace.chapters[index].cardID = card.id
            } else {
                workspace.chapters.append(ChapterDocument(
                    id: UUID(),
                    number: card.number,
                    volumeNumber: card.volumeNumber,
                    title: card.title,
                    cardID: card.id,
                    status: .planned,
                    currentVersionID: nil,
                    candidateVersionID: nil,
                    versions: []
                ))
            }
        }
        workspace.chapters.sort { $0.number < $1.number }
        if workspace.selectedChapterID == nil { workspace.selectedChapterID = workspace.chapters.first?.id }
    }

    private static func makeContinuityIssues(_ payload: CreativeGenerationPayload) -> [ContinuityIssue] {
        payload.items.map { item in
            let kind = item.kind.lowercased()
            let severity: ContinuitySeverity = kind.contains("block") || kind.contains("严重")
                ? .blocker
                : kind.contains("warn") || kind.contains("警告") ? .warning : .info
            return ContinuityIssue(
                id: UUID(),
                severity: severity,
                category: item.name,
                chapterNumbers: [],
                evidence: item.content,
                suggestion: item.details.joined(separator: "\n")
            )
        }
    }

    private static func bibleKind(_ value: String) -> StoryBibleCardKind {
        let lowered = value.lowercased()
        if lowered.contains("character") || value.contains("人物") { return .character }
        if lowered.contains("location") || value.contains("地点") { return .location }
        if lowered.contains("faction") || value.contains("势力") { return .faction }
        if lowered.contains("item") || value.contains("物品") { return .item }
        if lowered.contains("ability") || value.contains("能力") { return .ability }
        if lowered.contains("style") || value.contains("文风") { return .style }
        return .worldRule
    }

    private static func wordCount(_ value: String) -> Int {
        value.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }
}
