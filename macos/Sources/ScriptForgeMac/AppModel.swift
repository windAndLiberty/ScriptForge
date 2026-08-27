import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var project: StoredProject
    @Published private(set) var projectLibrary: [StoredProject]
    @Published private(set) var promptAssets: [PromptAsset]
    @Published private(set) var creativePromptOverrides: [CreativePromptOverride]
    @Published private(set) var creativeRuns: [WorkflowRun]
    @Published var primaryView = PrimaryView.studio
    @Published var activeTab = StudioTab.outline
    @Published var selectedChapter = 0
    @Published var selectedEpisode = 0
    @Published var pipelineProgress = PipelineProgress()
    @Published var bookProgress = BookAnalysisProgress()
    @Published var isRunning = false
    @Published var isNaming = false
    @Published var isProducing = false
    @Published var selectedShot = 0
    @Published var storyboardProgress = PipelineProgress()
    @Published var presentedError: String?
    @Published var toast: LocalizedHint?
    @Published var showSettings = false
    @Published var pendingDelete: StoredProject?
    @Published var pendingCreativeHandoff = false
    @Published var modelSettings: ModelSettings
    @Published private(set) var hasAPIKey: Bool
    @Published var selectedCreativeWorkflow = CreativeWorkflowID.incubation
    @Published var selectedCreativeRunID: UUID?
    @Published var selectedCreativeChapterID: UUID?
    @Published var creativeEditorText = ""
    @Published var creativePromptPreview = ""
    @Published var isCreativeRunning = false

    private let projects: ProjectRepository
    private let prompts: PromptAssetRepository
    private let creativePrompts: CreativePromptRepository
    private let defaults: UserDefaults
    private let apiKeyLoader: () -> String?
    private let apiKeySaver: (String) throws -> Void
    private var activeTask: Task<Void, Never>?
    private var creativeAutosaveTask: Task<Void, Never>?
    private var audioPlayer: NSSound?

    private static let apiKeyAvailabilityDefaultsKey = "hasStoredAPIKey.v1"

    init(
        projectRepository: ProjectRepository = ProjectRepository(),
        promptRepository: PromptAssetRepository = PromptAssetRepository(),
        creativePromptRepository: CreativePromptRepository = CreativePromptRepository(),
        modelSettingsOverride: ModelSettings? = nil,
        userDefaults: UserDefaults = .standard,
        apiKeyLoader: @escaping () -> String? = KeychainStore.load,
        apiKeySaver: @escaping (String) throws -> Void = KeychainStore.save
    ) {
        projects = projectRepository
        prompts = promptRepository
        creativePrompts = creativePromptRepository
        defaults = userDefaults
        self.apiKeyLoader = apiKeyLoader
        self.apiKeySaver = apiKeySaver
        let loadedProjects = projectRepository.loadAll()
        let loadedPromptAssets = promptRepository.load()
        projectLibrary = loadedProjects
        promptAssets = loadedPromptAssets
        creativePromptOverrides = creativePromptRepository.load(legacyAssets: loadedPromptAssets)
        let resolvedModelSettings = modelSettingsOverride ?? Self.loadModelSettings(from: userDefaults)
        modelSettings = resolvedModelSettings
        hasAPIKey = (userDefaults.object(forKey: Self.apiKeyAvailabilityDefaultsKey) as? Bool)
            ?? (resolvedModelSettings.useOnline && resolvedModelSettings.hasEndpointConsent)
        let savedID = userDefaults.string(forKey: "currentProjectID")
            .flatMap { UUID(uuidString: $0) }
        let initialProject = loadedProjects.first(where: { $0.id == savedID && $0.archivedAt == nil })
            ?? loadedProjects.first(where: { $0.archivedAt == nil })
            ?? StoredProject()
        project = initialProject
        let initialCreativeRuns = projectRepository.loadWorkflowRuns(projectID: initialProject.id)
        creativeRuns = initialCreativeRuns
        selectedCreativeRunID = initialCreativeRuns.first?.id
        selectedCreativeChapterID = initialProject.creativeWorkspace?.selectedChapterID
    }

    deinit {
        activeTask?.cancel()
        creativeAutosaveTask?.cancel()
    }

    var recentProjects: [StoredProject] { projectLibrary.filter { $0.archivedAt == nil } }
    var archivedProjects: [StoredProject] { projectLibrary.filter { $0.archivedAt != nil } }
    var modelReady: Bool {
        modelSettings.useOnline && hasAPIKey && modelSettings.hasEndpointConsent
    }

    private func loadAPIKeyForUserInitiatedAction() -> String {
        let key = apiKeyLoader()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateAPIKeyAvailability(!key.isEmpty)
        return key
    }

    private func updateAPIKeyAvailability(_ isAvailable: Bool) {
        hasAPIKey = isAvailable
        defaults.set(isAvailable, forKey: Self.apiKeyAvailabilityDefaultsKey)
    }

    func chooseNovel() {
        let panel = NSOpenPanel()
        panel.title = ui("导入故事或剧本", "Import Story or Script")
        panel.allowedContentTypes = DocumentImporter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importNovel(from: url)
    }

    func createCreativeProject() {
        if project.hasContent { persistCurrent() }
        var fresh = StoredProject(name: ui("新建网文项目", "New Web Novel Project"))
        fresh.creativeWorkspace = CreativeWorkspace()
        project = fresh
        creativeRuns = []
        selectedCreativeRunID = nil
        selectedCreativeChapterID = nil
        creativeEditorText = ""
        primaryView = .creation
        persistCurrent()
    }

    func chooseCreativeSource() {
        let panel = NSOpenPanel()
        panel.title = ui("导入网文或故事素材", "Import Web Novel or Story Material")
        panel.allowedContentTypes = DocumentImporter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importCreativeSource(from: url)
    }

    func importCreativeSource(from url: URL) {
        do {
            try withSecurityScopedAccess(to: url) {
                try performCreativeImport(from: url)
            }
        } catch { present(error) }
    }

    @discardableResult
    func importDroppedFiles(
        _ urls: [URL],
        route: DocumentImportRoute
    ) -> Bool {
        do {
            let request = try DocumentDropRequest.resolve(urls: urls, route: route)
            try withSecurityScopedAccess(to: request.url) {
                switch request.route {
                case .adaptation:
                    try performAdaptationImport(from: request.url)
                case .creation:
                    try performCreativeImport(from: request.url)
                }
            }
            showToast(
                "已通过拖拽导入 \(request.url.lastPathComponent)",
                "Imported \(request.url.lastPathComponent) by drag and drop"
            )
            return true
        } catch {
            present(error)
            return false
        }
    }

    func openCreationWorkspace() {
        if project.creativeWorkspace == nil {
            do {
                if let document = project.document {
                    project.creativeWorkspace = try importedCreativeWorkspace(
                        document: document,
                        projectID: project.id
                    )
                } else {
                    project.creativeWorkspace = CreativeWorkspace()
                }
                persistCurrent()
            } catch {
                present(error)
                return
            }
        }
        creativeRuns = projects.loadWorkflowRuns(projectID: project.id)
        selectedCreativeRunID = creativeRuns.first?.id
        selectedCreativeChapterID = project.creativeWorkspace?.selectedChapterID
        loadSelectedCreativeChapter()
        primaryView = .creation
    }

    func startCreativeWorkflow(
        seed: String,
        instruction: String,
        batchCount: Int,
        chapterCount: Int,
        disabledStepIDs: Set<String> = [],
        excludedContextIDs: Set<String> = []
    ) {
        guard !isCreativeRunning, !isRunning, !isProducing else { return }
        if project.creativeWorkspace == nil { project.creativeWorkspace = CreativeWorkspace() }
        guard let workspace = project.creativeWorkspace else { return }
        var input = WorkflowRunInput()
        input.seed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        input.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        input.batchCount = max(1, min(batchCount, 10))
        input.parameters["chapterCount"] = String(max(1, min(chapterCount, 200)))
        input.disabledStepIDs = disabledStepIDs
        input.excludedContextIDs = excludedContextIDs
        if [.chapterProduction, .continuityAudit, .chapterPolish].contains(selectedCreativeWorkflow) {
            input.selectedChapterIDs = selectedChapterBatch(
                workspace: workspace,
                count: selectedCreativeWorkflow == .chapterPolish ? 1 : input.batchCount
            )
            if input.selectedChapterIDs.isEmpty {
                return present(CreativeWorkflowError.noSelectedChapter)
            }
        }
        if selectedCreativeWorkflow == .incubation && input.seed.isEmpty {
            return present(CreativePromptError.missingVariables(["灵感或题材"]))
        }
        var run = WorkflowEngine.start(workflowID: selectedCreativeWorkflow, input: input)
        if modelReady {
            run.modelNames = [
                .primary: modelSettings.primaryModel,
                .flash: modelSettings.flashModel,
            ]
            run.endpointHost = modelSettings.endpointHost
        }
        creativeRuns.insert(run, at: 0)
        selectedCreativeRunID = run.id
        updateRunReference(run)
        do { try projects.writeWorkflowRun(run, projectID: project.id) }
        catch { return present(error) }
        persistCurrent()
        executeCreativeRun(runID: run.id)
    }

    func approveCreativeRun(_ runID: UUID) {
        guard let index = creativeRuns.firstIndex(where: { $0.id == runID }),
              var workspace = project.creativeWorkspace else { return }
        var run = creativeRuns[index]
        let approvalID = run.steps.indices.contains(run.activeStepIndex)
            ? run.steps[run.activeStepIndex].id
            : ""
        if (run.workflowID == .chapterProduction && approvalID == "approve-drafts")
            || run.workflowID == .chapterPolish {
            let pending = workspace.chapters.contains { chapter in
                run.input.selectedChapterIDs.contains(chapter.id) && chapter.candidateVersionID != nil
            }
            if pending { return present(CreativeWorkflowError.approvalRequired) }
            for artifactIndex in workspace.artifacts.indices where
                workspace.artifacts[artifactIndex].runID == run.id
                && workspace.artifacts[artifactIndex].isCandidate {
                workspace.artifacts[artifactIndex].isCandidate = false
            }
        } else {
            do {
                try CreativeWorkspaceService.acceptCurrentArtifact(
                    run: run,
                    workspace: &workspace,
                    repository: projects,
                    projectID: project.id
                )
            } catch { return present(error) }
        }
        do { run = try WorkflowEngine.approve(run) }
        catch { return present(error) }
        project.creativeWorkspace = workspace
        creativeRuns[index] = run
        updateRunReference(run)
        try? projects.writeWorkflowRun(run, projectID: project.id)
        persistCurrent()
        executeCreativeRun(runID: runID)
    }

    func resumeCreativeRun(_ runID: UUID) {
        guard let index = creativeRuns.firstIndex(where: { $0.id == runID }) else { return }
        let run = WorkflowEngine.resume(creativeRuns[index])
        creativeRuns[index] = run
        updateRunReference(run)
        try? projects.writeWorkflowRun(run, projectID: project.id)
        persistCurrent()
        executeCreativeRun(runID: runID)
    }

    func regenerateCreativeRun(_ runID: UUID) {
        guard let index = creativeRuns.firstIndex(where: { $0.id == runID }),
              var workspace = project.creativeWorkspace else { return }
        do {
            for chapterIndex in workspace.chapters.indices where
                creativeRuns[index].input.selectedChapterIDs.contains(workspace.chapters[chapterIndex].id) {
                workspace.chapters[chapterIndex].candidateVersionID = nil
                if workspace.chapters[chapterIndex].status == .review {
                    workspace.chapters[chapterIndex].status = workspace.chapters[chapterIndex].currentVersionID == nil
                        ? .planned
                        : .accepted
                }
            }
            let run = try WorkflowEngine.regenerate(creativeRuns[index])
            creativeRuns[index] = run
            project.creativeWorkspace = workspace
            updateRunReference(run)
            try projects.writeWorkflowRun(run, projectID: project.id)
            persistCurrent()
            executeCreativeRun(runID: runID)
        } catch { present(error) }
    }

    func cancelCreativeRun(_ runID: UUID) {
        guard let index = creativeRuns.firstIndex(where: { $0.id == runID }) else { return }
        activeTask?.cancel()
        let run = WorkflowEngine.cancel(creativeRuns[index])
        creativeRuns[index] = run
        isCreativeRunning = false
        updateRunReference(run)
        try? projects.writeWorkflowRun(run, projectID: project.id)
        persistCurrent()
    }

    func selectCreativeChapter(_ chapterID: UUID) {
        selectedCreativeChapterID = chapterID
        project.creativeWorkspace?.selectedChapterID = chapterID
        loadSelectedCreativeChapter()
        persistCurrent()
    }

    func updateCreativeEditorText(_ value: String) {
        creativeEditorText = value
        guard let chapterID = selectedCreativeChapterID else { return }
        creativeAutosaveTask?.cancel()
        let projectID = project.id
        creativeAutosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, self?.project.id == projectID else { return }
            do {
                try self?.projects.writeChapterWorkingDraft(
                    value,
                    chapterID: chapterID,
                    projectID: projectID
                )
            } catch { self?.present(error) }
        }
    }

    func saveCreativeChapterVersion() {
        guard let chapterID = selectedCreativeChapterID,
              var workspace = project.creativeWorkspace else { return }
        do {
            try CreativeWorkspaceService.saveManualChapter(
                chapterID: chapterID,
                content: creativeEditorText,
                workspace: &workspace,
                repository: projects,
                projectID: project.id
            )
            project.creativeWorkspace = workspace
            persistCurrent()
            showToast("章节版本已保存", "Chapter version saved")
        } catch { present(error) }
    }

    func acceptCreativeChapterCandidate(_ chapterID: UUID) {
        guard var workspace = project.creativeWorkspace else { return }
        do {
            try CreativeWorkspaceService.acceptChapterCandidate(
                chapterID: chapterID,
                workspace: &workspace
            )
            project.creativeWorkspace = workspace
            selectedCreativeChapterID = chapterID
            loadSelectedCreativeChapter(ignoreWorkingDraft: true)
            try? projects.writeChapterWorkingDraft(
                creativeEditorText,
                chapterID: chapterID,
                projectID: project.id
            )
            persistCurrent()
            if let runID = selectedCreativeRunID,
               let run = creativeRuns.first(where: { $0.id == runID }),
               run.status == .waitingForApproval,
               !workspace.chapters.contains(where: {
                   run.input.selectedChapterIDs.contains($0.id) && $0.candidateVersionID != nil
               }) {
                approveCreativeRun(runID)
            }
        } catch { present(error) }
    }

    func rejectCreativeChapterCandidate(_ chapterID: UUID) {
        guard var workspace = project.creativeWorkspace else { return }
        do {
            try CreativeWorkspaceService.rejectChapterCandidate(
                chapterID: chapterID,
                workspace: &workspace
            )
            project.creativeWorkspace = workspace
            loadSelectedCreativeChapter(ignoreWorkingDraft: true)
            persistCurrent()
        } catch { present(error) }
    }

    func restoreCreativeChapterVersion(_ versionID: UUID) {
        guard let chapterID = selectedCreativeChapterID,
              var workspace = project.creativeWorkspace else { return }
        do {
            try CreativeWorkspaceService.restoreVersion(
                chapterID: chapterID,
                versionID: versionID,
                workspace: &workspace,
                repository: projects,
                projectID: project.id
            )
            project.creativeWorkspace = workspace
            loadSelectedCreativeChapter(ignoreWorkingDraft: true)
            persistCurrent()
            showToast("已恢复为新的章节版本", "Restored as a new chapter version")
        } catch { present(error) }
    }

    func updateCreativePrompt(_ workflowID: CreativeWorkflowID, instruction: String) {
        guard let index = creativePromptOverrides.firstIndex(where: { $0.workflowID == workflowID }) else { return }
        creativePromptOverrides[index] = creativePrompts.updated(
            creativePromptOverrides[index],
            instruction: instruction
        )
        do { try creativePrompts.save(creativePromptOverrides) }
        catch { present(error) }
    }

    func resetCreativePrompt(_ workflowID: CreativeWorkflowID) {
        guard let index = creativePromptOverrides.firstIndex(where: { $0.workflowID == workflowID }) else { return }
        creativePromptOverrides[index] = creativePrompts.reset(workflowID)
        do {
            try creativePrompts.save(creativePromptOverrides)
            showToast("创作提示词已恢复默认", "Authoring prompt restored to default")
        } catch { present(error) }
    }

    func restoreCreativePromptRevision(_ workflowID: CreativeWorkflowID, revisionID: UUID) {
        guard let index = creativePromptOverrides.firstIndex(where: { $0.workflowID == workflowID }),
              let revision = creativePromptOverrides[index].revisions.first(where: { $0.id == revisionID }) else { return }
        creativePromptOverrides[index] = creativePrompts.updated(
            creativePromptOverrides[index],
            instruction: revision.instruction
        )
        do {
            try creativePrompts.save(creativePromptOverrides)
            showToast("已恢复提示词历史版本", "Prompt revision restored")
        } catch { present(error) }
    }

    func updateCreativeProjectInstruction(_ value: String, workflowID: CreativeWorkflowID) {
        if project.creativeWorkspace == nil { project.creativeWorkspace = CreativeWorkspace() }
        project.creativeWorkspace?.projectPromptInstructions[workflowID] = value
        persistCurrent()
    }

    func updateCreativeBrief(_ value: CreativeBrief) {
        guard var workspace = project.creativeWorkspace,
              let index = workspace.briefs.firstIndex(where: { $0.id == value.id }) else { return }
        workspace.briefs[index] = value
        project.creativeWorkspace = workspace
        persistCurrent()
    }

    func updateCreativeStoryBibleCard(_ value: StoryBibleCard) {
        guard var workspace = project.creativeWorkspace,
              let bibleIndex = workspace.storyBibles.firstIndex(where: { $0.id == workspace.activeStoryBible?.id }),
              let cardIndex = workspace.storyBibles[bibleIndex].cards.firstIndex(where: { $0.id == value.id })
        else { return }
        workspace.storyBibles[bibleIndex].cards[cardIndex] = value
        project.creativeWorkspace = workspace
        persistCurrent()
    }

    func updateCreativeChapterCard(_ value: ChapterCard) {
        guard var workspace = project.creativeWorkspace else { return }
        for outlineIndex in workspace.outlines.indices {
            if let cardIndex = workspace.outlines[outlineIndex].chapterCards.firstIndex(where: { $0.id == value.id }) {
                workspace.outlines[outlineIndex].chapterCards[cardIndex] = value
                if let chapterIndex = workspace.chapters.firstIndex(where: { $0.cardID == value.id }) {
                    workspace.chapters[chapterIndex].title = value.title
                }
                project.creativeWorkspace = workspace
                persistCurrent()
                return
            }
        }
    }

    func refreshCreativePromptPreview(seed: String, instruction: String) {
        var input = WorkflowRunInput()
        input.seed = seed
        input.instruction = instruction
        input.selectedChapterIDs = selectedCreativeChapterID.map { [$0] } ?? []
        let run = WorkflowEngine.start(workflowID: selectedCreativeWorkflow, input: input)
        do { creativePromptPreview = try compileCreativePrompt(for: run).snapshot.assembledPrompt }
        catch { creativePromptPreview = error.localizedDescription }
    }

    func creativeContextOptions() -> [CreativeContextOption] {
        let workspace = project.creativeWorkspace ?? CreativeWorkspace()
        let ids = selectedCreativeChapterID.map { [$0] } ?? []
        return CreativeContextBuilder.build(
            workspace: workspace,
            selectedChapterContents: creativeChapterContents(workspace: workspace, chapterIDs: ids)
        ).map { CreativeContextOption(id: $0.id, label: $0.label) }
    }

    func creativeArtifactMarkdown(_ reference: WorkflowArtifactReference) -> String {
        guard reference.kind != .promptSnapshot,
              let payload = try? projects.readCreativeArtifact(
                CreativeGenerationPayload.self,
                relativePath: reference.contentPath,
                projectID: project.id
              ) else { return reference.summary }
        return payload.markdown
    }

    func creativeChapterVersionText(_ version: ChapterVersion) -> String {
        (try? projects.readCreativeText(
            relativePath: version.contentPath,
            projectID: project.id
        )) ?? ""
    }

    func exportCreative(_ format: CreativeExportFormat) {
        do {
            let export = try CreativeExporter.makeExport(project: project, repository: projects)
            switch format {
            case .markdown:
                saveData(
                    Data(CreativeExporter.markdown(export).utf8),
                    suggestedName: project.name,
                    fileExtension: "md",
                    contentType: UTType(filenameExtension: "md") ?? .plainText
                )
            case .json:
                saveData(
                    try CreativeExporter.json(export),
                    suggestedName: "\(project.name)·创作工程",
                    fileExtension: "json",
                    contentType: .json
                )
            case .docx:
                saveData(
                    try CreativeExporter.docx(export),
                    suggestedName: project.name,
                    fileExtension: "docx",
                    contentType: UTType(filenameExtension: "docx") ?? .data
                )
            }
        } catch { present(error) }
    }

    func requestCreativeHandoff() { pendingCreativeHandoff = true }

    func confirmCreativeHandoff() {
        pendingCreativeHandoff = false
        do {
            let export = try CreativeExporter.makeExport(project: project, repository: projects)
            let chapters = export.chapters.map { chapter in
                Chapter(
                    id: "creative-\(chapter.versionID.uuidString)",
                    index: chapter.number,
                    title: chapter.title,
                    content: chapter.content,
                    characterCount: chapter.content.count
                )
            }
            let rawText = chapters.map { "第\($0.index)章 \($0.title)\n\($0.content)" }
                .joined(separator: "\n\n")
            let document = NovelDocument(
                fileName: "\(safeFileName(project.name)).md",
                title: project.name,
                author: "",
                intro: export.brief?.premise ?? "",
                rawText: rawText,
                characterCount: rawText.count,
                chapters: chapters,
                sourceKind: .prose,
                diagnostics: []
            )
            var workspace = project.creativeWorkspace ?? CreativeWorkspace()
            workspace.handoffSnapshots.append(CreativeHandoffSnapshot(
                id: UUID(),
                createdAt: Date(),
                chapterVersionIDs: export.chapters.map(\.versionID),
                document: document
            ))
            project.creativeWorkspace = workspace
            project.document = document
            project.characters = CharacterExtractor.extract(from: document)
            project.options.episodeCount = min(24, max(3, chapters.count))
            project.result = nil
            project.productionPackage = nil
            project.phase = .naming
            selectedChapter = 0
            selectedEpisode = 0
            selectedShot = 0
            primaryView = .studio
            activeTab = .outline
            persistCurrent()
            generateNamesIfAvailable()
            showToast(
                "已创建移交快照并送入改编工坊",
                "Handoff snapshot created and sent to Adaptation Studio"
            )
        } catch { present(error) }
    }

    func importNovel(from url: URL) {
        do {
            try withSecurityScopedAccess(to: url) {
                try performAdaptationImport(from: url)
            }
        } catch {
            present(error)
        }
    }

    private func performAdaptationImport(from url: URL) throws {
        let document = try DocumentImporter.load(from: url)
        if project.hasContent { persistCurrent() }
        let isScreenplay = document.resolvedSourceKind == .screenplay
        let projectSuffix = isScreenplay
            ? ui("分镜项目", "Storyboard Project")
            : ui("短剧改编", "Short Drama Adaptation")
        var fresh = StoredProject(name: "\(document.title) · \(projectSuffix)")
        fresh.document = document
        fresh.characters = isScreenplay
            ? ScreenplayPipeline.characters(from: document)
            : CharacterExtractor.extract(from: document)
        fresh.options.episodeCount = isScreenplay
            ? document.chapters.count
            : min(24, max(3, document.chapters.count))
        if isScreenplay {
            let result = try ScreenplayPipeline.run(
                document: document,
                characters: fresh.characters,
                options: fresh.options
            )
            fresh.result = result
            fresh.phase = result.quality.passed ? .completed : .quality
        } else {
            fresh.phase = .naming
        }
        project = fresh
        selectedChapter = 0
        selectedEpisode = 0
        selectedShot = 0
        primaryView = .studio
        activeTab = isScreenplay ? .script : .outline
        pipelineProgress = isScreenplay
            ? PipelineProgress(
                phase: fresh.phase,
                detail: ui(
                    "已保留 \(document.chapters.count) 集原稿结构，可直接生成分镜",
                    "Preserved \(document.chapters.count) source episode(s); ready for storyboarding"
                ),
                fraction: 1
            )
            : PipelineProgress(
                phase: .naming,
                detail: ui(
                    "已拆解 \(document.chapters.count) 章，正在准备人物新名",
                    "Parsed \(document.chapters.count) chapter(s); preparing character names"
                ),
                fraction: 0.12
            )
        persistCurrent()
        if isScreenplay {
            if let result = project.result {
                try? projects.writeArtifact(result.storyBible, name: "story-bible", projectID: project.id)
                try? projects.writeArtifact(result.quality, name: "quality-gate", projectID: project.id)
            }
            showToast(
                "已有剧本已按原稿结构导入",
                "Existing screenplay imported with its original structure"
            )
        } else {
            generateNamesIfAvailable()
        }
    }

    private func performCreativeImport(from url: URL) throws {
        let document = try DocumentImporter.load(from: url)
        if project.hasContent { persistCurrent() }
        var fresh = StoredProject(name: "\(document.title) · \(ui("创作项目", "Authoring Project"))")
        fresh.document = document
        fresh.creativeWorkspace = try importedCreativeWorkspace(
            document: document,
            projectID: fresh.id
        )
        project = fresh
        creativeRuns = []
        selectedCreativeRunID = nil
        selectedCreativeChapterID = fresh.creativeWorkspace?.selectedChapterID
        loadSelectedCreativeChapter()
        primaryView = .creation
        persistCurrent()
        showToast(
            "原稿已导入创作工坊，正文保持本地",
            "Manuscript imported into Author Studio; the text remains local"
        )
    }

    private func withSecurityScopedAccess(
        to url: URL,
        perform operation: () throws -> Void
    ) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        try operation()
    }

    func runAdaptation() {
        guard let document = project.document else { return present(PipelineError.noDocument) }
        if document.resolvedSourceKind == .screenplay {
            refreshImportedScreenplay(document)
            return
        }
        guard CharacterExtractor.validate(project.characters) else { return present(PipelineError.invalidNames) }
        guard !isRunning else { return }
        let settings = modelSettings
        let key = loadAPIKeyForUserInitiatedAction()
        if settings.useOnline {
            guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
            guard settings.hasEndpointConsent else {
                return present(ModelError.endpointConsentRequired(settings.endpointHost))
            }
        }

        isRunning = true
        project.phase = .analysis
        activeTab = .outline
        let uiLanguage = interfaceLanguage
        pipelineProgress = PipelineProgress(
            phase: .analysis,
            detail: ui("正在启动可信改编管线", "Starting the trusted adaptation pipeline"),
            fraction: 0.03
        )
        persistCurrent()
        let characters = project.characters
        let options = project.options
        let assets = promptAssets
        activeTask = Task {
            do {
                let result: AdaptationResult
                if settings.useOnline {
                    result = try await OnlinePipeline.run(
                        document: document,
                        characters: characters,
                        options: options,
                        prompts: assets,
                        settings: settings,
                        apiKey: key,
                        interfaceLanguage: uiLanguage
                    ) { [weak self] phase, detail, fraction in
                        Task { @MainActor in
                            self?.project.phase = phase
                            self?.pipelineProgress = PipelineProgress(
                                phase: phase,
                                detail: detail,
                                fraction: fraction
                            )
                        }
                    }
                } else {
                    for (phase, chinese, english, fraction) in Self.offlineSteps {
                        try Task.checkCancellation()
                        project.phase = phase
                        pipelineProgress = PipelineProgress(
                            phase: phase,
                            detail: uiLanguage == .english ? english : chinese,
                            fraction: fraction
                        )
                        try await Task.sleep(for: .milliseconds(120))
                    }
                    result = try OfflinePipeline.run(
                        document: document,
                        characters: characters,
                        options: options
                    )
                }
                project.result = result
                project.productionPackage = nil
                project.phase = result.quality.passed ? .completed : .quality
                project.checkpoints.append(PipelineCheckpoint(
                    id: UUID().uuidString,
                    phase: project.phase,
                    inputHash: Self.inputHash(document),
                    promptVersion: PromptAssets.version,
                    completedAt: Date()
                ))
                pipelineProgress = PipelineProgress(
                    phase: project.phase,
                    detail: result.quality.passed
                        ? (uiLanguage == .english
                            ? "Completed \(result.episodes.count) episode(s); quality gate passed"
                            : "已完成 \(result.episodes.count) 集，可信质量门通过")
                        : (uiLanguage == .english
                            ? "Draft saved; \(result.quality.gate?.openIssueCount ?? 0) issue(s) need review"
                            : "成稿已保留，质检发现 \(result.quality.gate?.openIssueCount ?? 0) 条待复核问题"),
                    fraction: 1
                )
                selectedEpisode = 0
                activeTab = result.quality.passed ? .script : .quality
                try? projects.writeArtifact(result.storyBible, name: "story-bible", projectID: project.id)
                try? projects.writeArtifact(result.quality, name: "quality-gate", projectID: project.id)
                persistCurrent()
                if result.quality.passed {
                    showToast("改编完成，项目已自动保存", "Adaptation complete; project saved automatically")
                } else {
                    showToast("成稿已保存，请查看质检报告", "Draft saved; review the quality report")
                }
            } catch is CancellationError {
                project.phase = .idle
                pipelineProgress.detail = uiLanguage == .english
                    ? "Task cancelled; completed assets remain saved locally"
                    : "任务已取消，已完成资产仍保存在本地"
                persistCurrent()
            } catch {
                project.phase = .failed
                persistCurrent()
                present(error)
            }
            isRunning = false
            activeTask = nil
        }
    }

    var resolvedContentLanguage: AppLanguage {
        guard let document = project.document else { return project.options.targetLanguage }
        return project.options.outputLanguage(for: document)
    }

    func runBookAnalysis() {
        guard let document = project.document else { return present(PipelineError.noDocument) }
        guard !isRunning else { return }
        let language = project.options.outputLanguage(for: document)
        let uiLanguage = interfaceLanguage
        let settings = modelSettings
        let key = settings.useOnline ? loadAPIKeyForUserInitiatedAction() : ""
        if settings.useOnline {
            guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
            guard settings.hasEndpointConsent else {
                return present(ModelError.endpointConsentRequired(settings.endpointHost))
            }
        }
        isRunning = true
        primaryView = .bookAnalysis
        bookProgress = BookAnalysisProgress(
            detail: uiLanguage == .english ? "Preparing complete chapter evidence" : "准备完整章节证据",
            completed: 0,
            total: document.chapters.count,
            fraction: 0.02
        )
        activeTask = Task {
            do {
                let report: BookAnalysisReport
                if settings.useOnline {
                    report = try await BookAnalysisPipeline.runOnline(
                        document: document,
                        characters: project.characters,
                        prompts: promptAssets,
                        settings: settings,
                        apiKey: key,
                        language: language
                    ) { [weak self] detail, completed, total, fraction in
                        Task { @MainActor in
                            self?.bookProgress = BookAnalysisProgress(
                                detail: detail,
                                completed: completed,
                                total: total,
                                fraction: fraction
                            )
                        }
                    }
                } else {
                    try await Task.sleep(for: .milliseconds(180))
                    report = BookAnalysisPipeline.runOffline(
                        document: document,
                        characters: project.characters,
                        language: language
                    )
                }
                project.bookAnalysis = report
                project.bookAnalysisVersions.append(BookAnalysisVersion(
                    id: UUID(),
                    instruction: language == .english ? "Initial report" : "初始报告",
                    createdAt: Date(),
                    report: report
                ))
                project.bookAnalysisVersions = Array(project.bookAnalysisVersions.suffix(8))
                bookProgress = BookAnalysisProgress(
                    detail: uiLanguage == .english
                        ? "Book analysis complete — \(report.coveragePercent)% evidence coverage"
                        : "一键拆书完成，证据覆盖 \(report.coveragePercent)%",
                    completed: document.chapters.count,
                    total: document.chapters.count,
                    fraction: 1
                )
                try? projects.writeArtifact(report, name: "book-analysis", projectID: project.id)
                persistCurrent()
                showToast("一键拆书完成", "Book analysis complete")
            } catch is CancellationError {
                bookProgress.detail = uiLanguage == .english ? "Book analysis cancelled" : "拆书任务已取消"
            } catch {
                present(error)
            }
            isRunning = false
            activeTask = nil
        }
    }

    func reviseBookAnalysis(instruction: String, language: AppLanguage) {
        guard let report = project.bookAnalysis else { return present(PipelineError.noBookAnalysis) }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = loadAPIKeyForUserInitiatedAction()
        guard modelSettings.useOnline, !key.isEmpty else { return present(PipelineError.missingAPIKey) }
        guard modelSettings.hasEndpointConsent else {
            return present(ModelError.endpointConsentRequired(modelSettings.endpointHost))
        }
        isRunning = true
        activeTask = Task {
            do {
                let revised = try await BookAnalysisPipeline.revise(
                    report: report,
                    instruction: trimmed,
                    prompts: promptAssets,
                    settings: modelSettings,
                    apiKey: key,
                    language: report.outputLanguage ?? .chinese
                )
                project.bookAnalysis = revised
                project.bookAnalysisVersions.append(BookAnalysisVersion(
                    id: UUID(),
                    instruction: trimmed,
                    createdAt: Date(),
                    report: revised
                ))
                project.bookAnalysisVersions = Array(project.bookAnalysisVersions.suffix(8))
                persistCurrent()
                showToast("拆书报告已按指令更新", "Book analysis updated")
            } catch { present(error) }
            isRunning = false
            activeTask = nil
        }
    }

    func cancelCurrentTask() { activeTask?.cancel() }

    func newProject() {
        if project.hasContent { persistCurrent() }
        project = StoredProject()
        selectedChapter = 0
        selectedEpisode = 0
        selectedShot = 0
        creativeRuns = []
        selectedCreativeRunID = nil
        selectedCreativeChapterID = nil
        creativeEditorText = ""
        activeTab = .outline
        primaryView = .studio
        pipelineProgress = PipelineProgress()
        bookProgress = BookAnalysisProgress()
        defaults.removeObject(forKey: "currentProjectID")
        showToast("已新建空白项目", "New blank project created")
    }

    func resetToHome() {
        if project.hasContent { persistCurrent() }
        newProject()
        showToast(
            "已重置到初始首页；原项目保留在项目档案",
            "Returned to the start screen; the previous project remains in Projects"
        )
    }

    func openProject(_ value: StoredProject) {
        if project.hasContent { persistCurrent() }
        project = value
        selectedChapter = 0
        selectedEpisode = 0
        selectedShot = 0
        creativeRuns = projects.loadWorkflowRuns(projectID: value.id)
        selectedCreativeRunID = creativeRuns.first?.id
        selectedCreativeChapterID = value.creativeWorkspace?.selectedChapterID
        primaryView = value.creativeWorkspace != nil && value.document == nil ? .creation : .studio
        activeTab = value.result == nil ? .outline : .script
        defaults.set(value.id.uuidString, forKey: "currentProjectID")
        loadSelectedCreativeChapter()
    }

    func duplicateProject(_ value: StoredProject) {
        do {
            let (copy, library) = try projects.duplicate(value)
            projectLibrary = library
            openProject(copy)
            showToast("项目副本已创建", "Project duplicate created")
        } catch { present(error) }
    }

    func archiveProject(_ value: StoredProject) {
        do {
            projectLibrary = try projects.archive(value)
            if value.id == project.id { newProject() }
            showToast("项目已归档", "Project archived")
        } catch { present(error) }
    }

    func restoreProject(_ value: StoredProject) {
        do {
            projectLibrary = try projects.restore(value)
            if let restored = projectLibrary.first(where: { $0.id == value.id }) {
                openProject(restored)
            }
            showToast("项目已恢复到最近项目", "Project restored to Recent")
        } catch { present(error) }
    }

    func requestDelete(_ value: StoredProject) { pendingDelete = value }

    func confirmDelete() {
        guard let value = pendingDelete else { return }
        do {
            projectLibrary = try projects.delete(value)
            pendingDelete = nil
            if value.id == project.id { newProject() }
            showToast("项目已永久删除", "Project permanently deleted")
        } catch { present(error) }
    }

    func updateProjectName(_ name: String) {
        project.name = name
        persistCurrent()
    }

    func updateOptions(_ mutate: (inout AdaptationOptions) -> Void) {
        mutate(&project.options)
        if project.sourceKind == .screenplay {
            project.options.episodeCount = project.document?.chapters.count ?? project.options.episodeCount
        }
        persistCurrent()
    }

    func updateCharacter(id: String, targetName: String) {
        guard let index = project.characters.firstIndex(where: { $0.id == id }) else { return }
        project.characters[index].targetName = targetName
        project.characters[index].locked = true
        project.characters[index].nameSource = .manual
        persistCurrent()
    }

    func updateEpisodeContent(_ content: String) {
        guard
            var result = project.result,
            result.episodes.indices.contains(selectedEpisode)
        else { return }
        result.episodes[selectedEpisode].content = content
        project.result = result
        project.productionPackage = nil
        persistCurrent()
    }

    func updatePromptAsset(id: String, instruction: String) {
        guard let index = promptAssets.firstIndex(where: { $0.id == id }) else { return }
        promptAssets[index].instruction = instruction
        promptAssets[index].isDefault = false
        promptAssets[index].updatedAt = Date()
        do { try prompts.save(promptAssets) } catch { present(error) }
    }

    func resetPromptAsset(id: String) {
        guard let index = promptAssets.firstIndex(where: { $0.id == id }) else { return }
        promptAssets[index] = PromptAssets.reset(asset: promptAssets[index])
        do {
            try prompts.save(promptAssets)
            showToast("提示词已恢复默认", "Prompt restored to default")
        } catch { present(error) }
    }

    func saveSettings(_ settings: ModelSettings, apiKey: String, consentGranted: Bool) {
        var updated = settings
        updated.consentedEndpointHost = consentGranted ? updated.endpointHost : ""
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try apiKeySaver(trimmed)
                updateAPIKeyAvailability(true)
            }
            modelSettings = updated
            Self.persistModelSettings(updated, to: defaults)
            showSettings = false
            showToast("模型连接已保存", "Model connection saved")
        } catch { present(error) }
    }

    func exportScript() {
        guard let result = project.result else { return present(PipelineError.noResult) }
        let content = [
            "《\(project.name)》",
            "题材：\(result.genre)",
            "规格：\(result.episodes.count)集 × 约\(project.options.durationSeconds)秒",
            "一句话梗概：\(result.logline)",
            "提示：AI辅助内容，须经编剧、制片与合规人员复核。",
            "",
            result.episodes.map(\.content).joined(separator: "\n\n"),
        ].joined(separator: "\n")
        saveText(content, suggestedName: project.name, type: .plainText)
    }

    func exportBookAnalysis(language: AppLanguage) {
        guard let report = project.bookAnalysis else { return present(PipelineError.noBookAnalysis) }
        let reportLanguage = report.outputLanguage ?? .chinese
        saveText(
            BookAnalysisPipeline.renderMarkdown(report, language: reportLanguage),
            suggestedName: reportLanguage == .english
                ? "\(report.title) - Book Analysis"
                : "\(report.title)·拆书报告",
            type: UTType(filenameExtension: "md") ?? .plainText
        )
    }

    func generateStoryboards() {
        guard let result = project.result else { return present(PipelineError.noResult) }
        guard !isRunning, !isProducing else { return }
        let settings = modelSettings
        let key = loadAPIKeyForUserInitiatedAction()
        if settings.useOnline {
            guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
            guard settings.hasEndpointConsent else {
                return present(ModelError.endpointConsentRequired(settings.endpointHost))
            }
        }
        isProducing = true
        storyboardProgress = PipelineProgress(
            phase: .drafting,
            detail: ui(
                "正在从已批准剧本生成分镜制作包",
                "Generating a storyboard package from the approved script"
            ),
            fraction: 0.02
        )
        let projectID = project.id
        let characters = project.characters
        let duration = project.options.durationSeconds
        let assets = promptAssets
        activeTask = Task {
            defer {
                isProducing = false
                activeTask = nil
            }
            do {
                let package: ProductionPackage
                if settings.useOnline {
                    package = try await StoryboardPipeline.runOnline(
                        result: result,
                        characters: characters,
                        durationSeconds: duration,
                        prompts: assets,
                        settings: settings,
                        apiKey: key,
                        interfaceLanguage: interfaceLanguage
                    ) { [weak self] detail, fraction in
                        Task { @MainActor in
                            self?.storyboardProgress = PipelineProgress(
                                phase: .drafting,
                                detail: detail,
                                fraction: fraction
                            )
                        }
                    }
                } else {
                    try await Task.sleep(for: .milliseconds(160))
                    package = StoryboardPipeline.runOffline(
                        result: result,
                        characters: characters,
                        durationSeconds: duration
                    )
                }
                guard project.id == projectID else { return }
                project.productionPackage = package
                selectedEpisode = 0
                selectedShot = 0
                storyboardProgress = PipelineProgress(
                    phase: .completed,
                    detail: ui(
                        "已完成 \(package.episodes.count) 集、\(package.shotCount) 个镜头",
                        "Completed \(package.episodes.count) episode(s) and \(package.shotCount) shot(s)"
                    ),
                    fraction: 1
                )
                try? projects.writeArtifact(package, name: "storyboard-production", projectID: project.id)
                persistCurrent()
                showToast("分镜制作包已保存在本地", "Storyboard production package saved locally")
            } catch is CancellationError {
                storyboardProgress.detail = ui("分镜任务已取消", "Storyboard task cancelled")
            } catch { present(error) }
        }
    }

    func generateKeyframe(episodeIndex: Int, shotIndex: Int) {
        guard !isProducing else { return }
        guard modelSettings.useOnline,
              !modelSettings.imageModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return present(PipelineError.missingImageModel)
        }
        let key = loadAPIKeyForUserInitiatedAction()
        guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
        guard modelSettings.hasEndpointConsent else {
            return present(ModelError.endpointConsentRequired(modelSettings.endpointHost))
        }
        guard let package = project.productionPackage,
              package.episodes.indices.contains(episodeIndex),
              package.episodes[episodeIndex].shots.indices.contains(shotIndex) else {
            return present(PipelineError.noStoryboard)
        }
        let shot = package.episodes[episodeIndex].shots[shotIndex]
        let episodeNumber = package.episodes[episodeIndex].episodeNumber
        let projectID = project.id
        let settings = modelSettings
        isProducing = true
        activeTask = Task {
            defer {
                isProducing = false
                activeTask = nil
            }
            do {
                let client = LLMClient(settings: settings, apiKey: key)
                let data = try await client.generateImage(
                    prompt: "\(shot.imagePrompt)\nAvoid: \(shot.negativePrompt)",
                    model: settings.imageModel
                )
                let path = try projects.writeMedia(
                    data,
                    fileExtension: "png",
                    projectID: projectID,
                    episodeNumber: episodeNumber,
                    shotID: shot.id,
                    kind: "keyframe"
                )
                guard project.id == projectID,
                      var latest = project.productionPackage,
                      latest.episodes.indices.contains(episodeIndex),
                      latest.episodes[episodeIndex].shots.indices.contains(shotIndex) else { return }
                latest.episodes[episodeIndex].shots[shotIndex].keyframePath = path
                project.productionPackage = latest
                persistCurrent()
                showToast("首帧图片已保存到项目", "Keyframe image saved to the project")
            } catch { present(error) }
        }
    }

    func generateNarration(episodeIndex: Int, shotIndex: Int) {
        guard !isProducing else { return }
        guard modelSettings.useOnline,
              !modelSettings.speechModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return present(PipelineError.missingSpeechModel)
        }
        let key = loadAPIKeyForUserInitiatedAction()
        guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
        guard modelSettings.hasEndpointConsent else {
            return present(ModelError.endpointConsentRequired(modelSettings.endpointHost))
        }
        guard let package = project.productionPackage,
              package.episodes.indices.contains(episodeIndex),
              package.episodes[episodeIndex].shots.indices.contains(shotIndex) else {
            return present(PipelineError.noStoryboard)
        }
        let shot = package.episodes[episodeIndex].shots[shotIndex]
        let speechText = shot.narration.isEmpty ? shot.dialogue : shot.narration
        guard !speechText.isEmpty else { return present(PipelineError.noSpeechText) }
        let episodeNumber = package.episodes[episodeIndex].episodeNumber
        let projectID = project.id
        let settings = modelSettings
        isProducing = true
        activeTask = Task {
            defer {
                isProducing = false
                activeTask = nil
            }
            do {
                let client = LLMClient(settings: settings, apiKey: key)
                let data = try await client.synthesizeSpeech(
                    text: speechText,
                    model: settings.speechModel,
                    voice: settings.speechVoice
                )
                let path = try projects.writeMedia(
                    data,
                    fileExtension: "mp3",
                    projectID: projectID,
                    episodeNumber: episodeNumber,
                    shotID: shot.id,
                    kind: "voice"
                )
                guard project.id == projectID,
                      var latest = project.productionPackage,
                      latest.episodes.indices.contains(episodeIndex),
                      latest.episodes[episodeIndex].shots.indices.contains(shotIndex) else { return }
                latest.episodes[episodeIndex].shots[shotIndex].narrationPath = path
                project.productionPackage = latest
                persistCurrent()
                showToast("镜头配音已保存到项目", "Shot narration saved to the project")
            } catch { present(error) }
        }
    }

    func playNarration(relativePath: String) {
        guard let url = mediaURL(relativePath: relativePath) else { return }
        audioPlayer = NSSound(contentsOf: url, byReference: true)
        audioPlayer?.play()
    }

    func mediaURL(relativePath: String) -> URL? {
        projects.mediaURL(relativePath: relativePath, projectID: project.id)
    }

    func exportStoryboards() {
        guard let package = project.productionPackage else { return present(PipelineError.noStoryboard) }
        saveText(
            StoryboardPipeline.renderMarkdown(package, projectName: project.name),
            suggestedName: "\(project.name)·分镜制作包",
            type: UTType(filenameExtension: "md") ?? .plainText
        )
    }

    private func executeCreativeRun(runID: UUID) {
        guard !isCreativeRunning,
              let runIndex = creativeRuns.firstIndex(where: { $0.id == runID }) else { return }
        let run = creativeRuns[runIndex]
        let compiled: CompiledCreativePrompt
        do { compiled = try compileCreativePrompt(for: run) }
        catch { return present(error) }
        creativePromptPreview = compiled.snapshot.assembledPrompt
        let projectID = project.id
        let key = modelSettings.useOnline ? loadAPIKeyForUserInitiatedAction() : ""
        let client: (any CreativeWorkflowModelClient)? = modelReady && !key.isEmpty
            ? BYOKCreativeWorkflowModelClient(settings: modelSettings, apiKey: key)
            : nil
        isCreativeRunning = true
        activeTask = Task { [weak self] in
            guard let self else { return }
            let result = await WorkflowEngine.advance(
                run: run,
                prompt: compiled,
                modelClient: client
            )
            guard self.project.id == projectID,
                  let latestIndex = self.creativeRuns.firstIndex(where: { $0.id == runID }),
                  var workspace = self.project.creativeWorkspace else {
                self.isCreativeRunning = false
                return
            }
            var updatedRun = result.run
            do {
                try CreativeWorkspaceService.storePromptSnapshot(
                    compiled.snapshot,
                    run: &updatedRun,
                    workspace: &workspace,
                    repository: self.projects,
                    projectID: projectID
                )
                for generated in result.generated {
                    _ = try CreativeWorkspaceService.storePayload(
                        generated.payload,
                        stepID: generated.stepID,
                        run: &updatedRun,
                        workspace: &workspace,
                        repository: self.projects,
                        projectID: projectID
                    )
                }
                self.project.creativeWorkspace = workspace
                self.creativeRuns[latestIndex] = updatedRun
                self.updateRunReference(updatedRun)
                try self.projects.writeWorkflowRun(updatedRun, projectID: projectID)
                self.persistCurrent()
                if updatedRun.status == .waitingForModel {
                    self.showToast(
                        "本地步骤已完成；配置 BYOK 模型后可继续生成",
                        "Local steps complete; configure a BYOK model to continue generation"
                    )
                } else if updatedRun.status == .waitingForApproval {
                    self.showToast(
                        "候选结果已生成，等待作者确认",
                        "Candidate generated and awaiting author approval"
                    )
                    if let chapterID = updatedRun.input.selectedChapterIDs.first {
                        self.selectCreativeChapter(chapterID)
                    }
                } else if updatedRun.status == .completed {
                    self.showToast("工作流已完成", "Workflow complete")
                }
            } catch {
                updatedRun.status = .failed
                updatedRun.errorMessage = error.localizedDescription
                self.creativeRuns[latestIndex] = updatedRun
                self.updateRunReference(updatedRun)
                try? self.projects.writeWorkflowRun(updatedRun, projectID: projectID)
                self.present(error)
            }
            self.isCreativeRunning = false
            self.activeTask = nil
        }
    }

    private func compileCreativePrompt(for run: WorkflowRun) throws -> CompiledCreativePrompt {
        let workspace = project.creativeWorkspace ?? CreativeWorkspace()
        let selectedContents = creativeChapterContents(
            workspace: workspace,
            chapterIDs: run.input.selectedChapterIDs
        )
        var context = CreativeContextBuilder.build(
            workspace: workspace,
            selectedChapterContents: selectedContents
        )
        if let document = project.document,
           run.workflowID == .incubation || run.workflowID == .storyBible {
            context.append((
                id: "imported-source",
                label: "导入原稿",
                content: String(document.rawText.prefix(32_000))
            ))
        }
        let workflowOverride = creativePromptOverrides.first(where: { $0.workflowID == run.workflowID })
        return try CreativePromptCompiler.compile(
            workflowID: run.workflowID,
            workflowOverride: workflowOverride,
            projectInstruction: workspace.projectPromptInstructions[run.workflowID] ?? "",
            runInstruction: run.input.instruction,
            variables: [
                "seed": run.input.seed,
                "project_name": project.name,
                "batch_count": String(run.input.batchCount),
            ],
            context: context,
            excludedContextIDs: run.input.excludedContextIDs
        )
    }

    private func creativeChapterContents(
        workspace: CreativeWorkspace,
        chapterIDs: [UUID]
    ) -> [(id: UUID, title: String, content: String)] {
        let selected = chapterIDs.isEmpty
            ? Array(workspace.chapters.sorted { $0.number < $1.number }.suffix(3))
            : workspace.chapters.filter { chapterIDs.contains($0.id) }.sorted { $0.number < $1.number }
        return selected.compactMap { chapter in
            let versionID = chapter.candidateVersionID ?? chapter.currentVersionID
            guard let versionID,
                  let version = chapter.versions.first(where: { $0.id == versionID }),
                  let content = try? projects.readCreativeText(
                    relativePath: version.contentPath,
                    projectID: project.id
                  ) else { return nil }
            return (chapter.id, "第\(chapter.number)章 \(chapter.title)", content)
        }
    }

    private func selectedChapterBatch(workspace: CreativeWorkspace, count: Int) -> [UUID] {
        let sorted = workspace.chapters.sorted { $0.number < $1.number }
        guard !sorted.isEmpty else { return [] }
        let selectedID = selectedCreativeChapterID ?? workspace.selectedChapterID ?? sorted.first?.id
        let start = sorted.firstIndex(where: { $0.id == selectedID }) ?? 0
        return Array(sorted.dropFirst(start).prefix(max(1, min(count, 10))).map(\.id))
    }

    private func updateRunReference(_ run: WorkflowRun) {
        guard var workspace = project.creativeWorkspace else { return }
        let reference = WorkflowRunReference(
            id: run.id,
            workflowID: run.workflowID,
            status: run.status,
            updatedAt: run.updatedAt
        )
        if let index = workspace.runReferences.firstIndex(where: { $0.id == run.id }) {
            workspace.runReferences[index] = reference
        } else {
            workspace.runReferences.insert(reference, at: 0)
        }
        project.creativeWorkspace = workspace
    }

    private func loadSelectedCreativeChapter(ignoreWorkingDraft: Bool = false) {
        guard let workspace = project.creativeWorkspace,
              let chapterID = selectedCreativeChapterID ?? workspace.selectedChapterID,
              let chapter = workspace.chapters.first(where: { $0.id == chapterID }) else {
            creativeEditorText = ""
            return
        }
        if !ignoreWorkingDraft,
           chapter.candidateVersionID == nil,
           let working = projects.readChapterWorkingDraft(chapterID: chapterID, projectID: project.id) {
            creativeEditorText = working
            return
        }
        let versionID = chapter.candidateVersionID ?? chapter.currentVersionID
        guard let versionID,
              let version = chapter.versions.first(where: { $0.id == versionID }),
              let content = try? projects.readCreativeText(
                relativePath: version.contentPath,
                projectID: project.id
              ) else {
            creativeEditorText = ""
            return
        }
        creativeEditorText = content
    }

    private func importedCreativeWorkspace(
        document: NovelDocument,
        projectID: UUID
    ) throws -> CreativeWorkspace {
        var workspace = CreativeWorkspace()
        var cards: [ChapterCard] = []
        for chapter in document.chapters {
            let chapterID = UUID()
            let versionID = UUID()
            let path = try projects.writeChapterVersion(
                chapter.content,
                chapterID: chapterID,
                versionID: versionID,
                projectID: projectID
            )
            let card = ChapterCard(
                id: UUID(),
                number: chapter.index,
                volumeNumber: 1,
                title: chapter.title,
                objective: String(chapter.content.prefix(120)),
                conflict: "",
                reveal: "",
                hook: "",
                sceneBeats: [],
                activeForeshadowingIDs: []
            )
            cards.append(card)
            workspace.chapters.append(ChapterDocument(
                id: chapterID,
                number: chapter.index,
                volumeNumber: 1,
                title: chapter.title,
                cardID: card.id,
                status: .accepted,
                currentVersionID: versionID,
                candidateVersionID: nil,
                versions: [ChapterVersion(
                    id: versionID,
                    createdAt: Date(),
                    source: .imported,
                    contentPath: path,
                    summary: String(chapter.content.prefix(120)),
                    wordCount: chapter.characterCount,
                    promptSnapshotID: nil,
                    accepted: true
                )]
            ))
        }
        if !cards.isEmpty {
            workspace.outlines = [VolumeOutline(
                id: UUID(),
                number: 1,
                title: "导入原稿",
                arcSummary: document.intro,
                chapterCards: cards,
                createdAt: Date()
            )]
            workspace.selectedChapterID = workspace.chapters.first?.id
        }
        return workspace
    }

    private func saveData(
        _ data: Data,
        suggestedName: String,
        fileExtension: String,
        contentType: UTType
    ) {
        let panel = NSSavePanel()
        panel.title = ui("导出文件", "Export File")
        panel.nameFieldStringValue = "\(safeFileName(suggestedName)).\(fileExtension)"
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            showToast("文件已导出", "File exported")
        } catch { present(error) }
    }

    private func generateNamesIfAvailable() {
        let finishLocally = {
            self.project.characters = CharacterExtractor.resolveModelNames(
                characters: self.project.characters,
                proposals: []
            )
            self.project.phase = .idle
            self.persistCurrent()
        }
        guard
            let document = project.document,
            modelSettings.useOnline,
            modelSettings.hasEndpointConsent,
            !project.characters.isEmpty
        else {
            finishLocally()
            return
        }
        let key = loadAPIKeyForUserInitiatedAction()
        guard !key.isEmpty else {
            finishLocally()
            return
        }
        let projectID = project.id
        let original = project.characters
        let settings = modelSettings
        let assets = promptAssets
        isNaming = true
        Task {
            defer { isNaming = false }
            do {
                let renamed = try await OnlinePipeline.generateCharacterNames(
                    document: document,
                    characters: original,
                    prompts: assets,
                    settings: settings,
                    apiKey: key
                )
                guard project.id == projectID else { return }
                project.characters = renamed
                project.phase = .idle
                pipelineProgress = PipelineProgress(
                    phase: .idle,
                    detail: ui(
                        "人物新名已由高速模型生成，可继续手动修改",
                        "Character names generated by the fast model; manual editing remains available"
                    ),
                    fraction: 0.18
                )
                persistCurrent()
            } catch {
                guard project.id == projectID else { return }
                project.characters = CharacterExtractor.resolveModelNames(
                    characters: original,
                    proposals: []
                )
                project.phase = .idle
                pipelineProgress.detail = ui(
                    "高速命名不可用，已使用无占位名的本地安全候选",
                    "Fast naming unavailable; safe local names were used"
                )
                persistCurrent()
                showToast(
                    "人物命名已使用本地安全候选，可手动修改",
                    "Local safe character-name candidates applied; you can edit them manually"
                )
            }
        }
    }

    private func refreshImportedScreenplay(_ document: NovelDocument) {
        guard !isRunning else { return }
        isRunning = true
        project.phase = .analysis
        pipelineProgress = PipelineProgress(
            phase: .analysis,
            detail: ui(
                "正在重新解析原稿集、场、画面与对白结构",
                "Re-parsing source episodes, scenes, action, and dialogue"
            ),
            fraction: 0.2
        )
        do {
            project.options.episodeCount = document.chapters.count
            let result = try ScreenplayPipeline.run(
                document: document,
                characters: project.characters,
                options: project.options
            )
            project.result = result
            project.productionPackage = nil
            project.phase = result.quality.passed ? .completed : .quality
            selectedEpisode = 0
            selectedShot = 0
            activeTab = .script
            pipelineProgress = PipelineProgress(
                phase: project.phase,
                detail: ui(
                    "已按原稿保留 \(result.episodes.count) 集、\(result.episodes.reduce(0) { $0 + $1.scenes.count }) 场",
                    "Preserved \(result.episodes.count) episode(s) and \(result.episodes.reduce(0) { $0 + $1.scenes.count }) scene(s) from the source"
                ),
                fraction: 1
            )
            try? projects.writeArtifact(result.storyBible, name: "story-bible", projectID: project.id)
            try? projects.writeArtifact(result.quality, name: "quality-gate", projectID: project.id)
            persistCurrent()
            showToast(
                "剧本结构已刷新，旧分镜已失效",
                "Screenplay structure refreshed; the previous storyboard is now outdated"
            )
        } catch {
            project.phase = .failed
            present(error)
        }
        isRunning = false
    }

    private func persistCurrent() {
        guard project.hasContent else { return }
        project.updatedAt = Date()
        do {
            projectLibrary = try projects.save(project)
            if let saved = projectLibrary.first(where: { $0.id == project.id }) {
                project = saved
            }
            defaults.set(project.id.uuidString, forKey: "currentProjectID")
        } catch { present(error) }
    }

    private func saveText(_ value: String, suggestedName: String, type: UTType) {
        let panel = NSSavePanel()
        panel.title = ui("导出文件", "Export File")
        panel.nameFieldStringValue = "\(safeFileName(suggestedName)).\(type.preferredFilenameExtension ?? "txt")"
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try value.write(to: url, atomically: true, encoding: .utf8)
            showToast("文件已导出", "File exported")
        } catch { present(error) }
    }

    private func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[\\/:*?\"<>|]"#,
            with: "_",
            options: .regularExpression
        )
    }

    private var interfaceLanguage: AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: "uiLanguage") ?? "") ?? .chinese
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        interfaceLanguage == .english ? english : chinese
    }

    private func present(_ error: Error) {
        presentedError = LocalizationStore.errorText(
            error.localizedDescription,
            language: interfaceLanguage
        )
    }

    private func showToast(_ chinese: String, _ english: String) {
        let hint = LocalizedHint(chinese: chinese, english: english)
        toast = hint
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == hint { toast = nil }
        }
    }

    private static func loadModelSettings(from defaults: UserDefaults) -> ModelSettings {
        guard
            let data = defaults.data(forKey: "modelSettings.v2"),
            let settings = try? JSONDecoder.scriptForge.decode(ModelSettings.self, from: data)
        else { return ModelSettings() }
        return settings
    }

    private static func persistModelSettings(_ settings: ModelSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder.scriptForge.encode(settings) else { return }
        defaults.set(data, forKey: "modelSettings.v2")
    }

    private static func inputHash(_ document: NovelDocument) -> String {
        "\(document.characterCount)-\(document.chapters.count)-\(document.title.hashValue)"
    }

    private static let offlineSteps: [(PipelinePhase, String, String, Double)] = [
        (.analysis, "正在抽取故事事实、冲突和情绪爆点", "Extracting story facts, conflicts, and emotional peaks", 0.2),
        (.bible, "正在建立人物关系、世界规则和时间线", "Building relationships, world rules, and timeline", 0.38),
        (.outline, "正在重组分集目标、反转与动态场次", "Planning episode objectives, reversals, and scenes", 0.55),
        (.drafting, "正在生成场景动作和角色对白", "Drafting scene action and dialogue", 0.76),
        (.quality, "正在检查旧名、时长、连续性与钩子", "Checking names, runtime, continuity, and hooks", 0.92),
    ]
}

enum StudioTab: String, CaseIterable, Identifiable, Hashable {
    case outline
    case bible
    case script
    case storyboard
    case quality

    var id: String { rawValue }
}
