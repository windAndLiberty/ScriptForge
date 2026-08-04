import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var project: StoredProject
    @Published private(set) var projectLibrary: [StoredProject]
    @Published private(set) var promptAssets: [PromptAsset]
    @Published var primaryView = PrimaryView.studio
    @Published var activeTab = StudioTab.outline
    @Published var selectedChapter = 0
    @Published var selectedEpisode = 0
    @Published var pipelineProgress = PipelineProgress()
    @Published var bookProgress = BookAnalysisProgress()
    @Published var isRunning = false
    @Published var isNaming = false
    @Published var presentedError: String?
    @Published var toast: String?
    @Published var showSettings = false
    @Published var pendingDelete: StoredProject?
    @Published var modelSettings: ModelSettings

    private let projects: ProjectRepository
    private let prompts: PromptAssetRepository
    private var activeTask: Task<Void, Never>?

    init(
        projectRepository: ProjectRepository = ProjectRepository(),
        promptRepository: PromptAssetRepository = PromptAssetRepository()
    ) {
        projects = projectRepository
        prompts = promptRepository
        projectLibrary = projectRepository.loadAll()
        promptAssets = promptRepository.load()
        modelSettings = Self.loadModelSettings()
        let savedID = UserDefaults.standard.string(forKey: "currentProjectID")
            .flatMap { UUID(uuidString: $0) }
        project = projectLibrary.first(where: { $0.id == savedID && $0.archivedAt == nil })
            ?? projectLibrary.first(where: { $0.archivedAt == nil })
            ?? StoredProject()
    }

    deinit { activeTask?.cancel() }

    var hasAPIKey: Bool { !(KeychainStore.load() ?? "").isEmpty }
    var recentProjects: [StoredProject] { projectLibrary.filter { $0.archivedAt == nil } }
    var archivedProjects: [StoredProject] { projectLibrary.filter { $0.archivedAt != nil } }
    var modelReady: Bool {
        modelSettings.useOnline && hasAPIKey && modelSettings.hasEndpointConsent
    }

    func chooseNovel() {
        let panel = NSOpenPanel()
        panel.title = "导入小说文本"
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importNovel(from: url)
    }

    func importNovel(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let document = try NovelParser.parse(data: data, fileName: url.lastPathComponent)
            if project.hasContent { persistCurrent() }
            var fresh = StoredProject(name: "\(document.title)·短剧改编")
            fresh.document = document
            fresh.characters = CharacterExtractor.extract(from: document)
            fresh.options.episodeCount = min(24, max(3, document.chapters.count))
            fresh.phase = .naming
            project = fresh
            selectedChapter = 0
            selectedEpisode = 0
            primaryView = .studio
            activeTab = .outline
            pipelineProgress = PipelineProgress(
                phase: .naming,
                detail: "已拆解 \(document.chapters.count) 章，正在准备人物新名",
                fraction: 0.12
            )
            persistCurrent()
            generateNamesIfAvailable()
        } catch {
            present(error)
        }
    }

    func runAdaptation() {
        guard let document = project.document else { return present(PipelineError.noDocument) }
        guard CharacterExtractor.validate(project.characters) else { return present(PipelineError.invalidNames) }
        guard !isRunning else { return }
        let settings = modelSettings
        let key = KeychainStore.load() ?? ""
        if settings.useOnline {
            guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
            guard settings.hasEndpointConsent else {
                return present(ModelError.endpointConsentRequired(settings.endpointHost))
            }
        }

        isRunning = true
        project.phase = .analysis
        activeTab = .outline
        pipelineProgress = PipelineProgress(phase: .analysis, detail: "正在启动可信改编管线", fraction: 0.03)
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
                        apiKey: key
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
                    for (phase, detail, fraction) in Self.offlineSteps {
                        try Task.checkCancellation()
                        project.phase = phase
                        pipelineProgress = PipelineProgress(phase: phase, detail: detail, fraction: fraction)
                        try await Task.sleep(for: .milliseconds(120))
                    }
                    result = try OfflinePipeline.run(
                        document: document,
                        characters: characters,
                        options: options
                    )
                }
                project.result = result
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
                        ? "已完成 \(result.episodes.count) 集，可信质量门通过"
                        : "成稿已保留，质检发现 \(result.quality.gate?.openIssueCount ?? 0) 条待复核问题",
                    fraction: 1
                )
                selectedEpisode = 0
                activeTab = result.quality.passed ? .script : .quality
                try? projects.writeArtifact(result.storyBible, name: "story-bible", projectID: project.id)
                try? projects.writeArtifact(result.quality, name: "quality-gate", projectID: project.id)
                persistCurrent()
                showToast(result.quality.passed ? "改编完成，项目已自动保存" : "成稿已保存，请查看质检报告")
            } catch is CancellationError {
                project.phase = .idle
                pipelineProgress.detail = "任务已取消，已完成资产仍保存在本地"
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

    func runBookAnalysis() {
        guard let document = project.document else { return present(PipelineError.noDocument) }
        guard !isRunning else { return }
        let settings = modelSettings
        let key = KeychainStore.load() ?? ""
        if settings.useOnline {
            guard !key.isEmpty else { return present(PipelineError.missingAPIKey) }
            guard settings.hasEndpointConsent else {
                return present(ModelError.endpointConsentRequired(settings.endpointHost))
            }
        }
        isRunning = true
        primaryView = .bookAnalysis
        bookProgress = BookAnalysisProgress(detail: "准备完整章节证据", completed: 0, total: document.chapters.count, fraction: 0.02)
        activeTask = Task {
            do {
                let report: BookAnalysisReport
                if settings.useOnline {
                    report = try await BookAnalysisPipeline.runOnline(
                        document: document,
                        characters: project.characters,
                        prompts: promptAssets,
                        settings: settings,
                        apiKey: key
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
                        characters: project.characters
                    )
                }
                project.bookAnalysis = report
                project.bookAnalysisVersions.append(BookAnalysisVersion(
                    id: UUID(),
                    instruction: "初始报告",
                    createdAt: Date(),
                    report: report
                ))
                project.bookAnalysisVersions = Array(project.bookAnalysisVersions.suffix(8))
                bookProgress = BookAnalysisProgress(
                    detail: "一键拆书完成，证据覆盖 \(report.coveragePercent)%",
                    completed: document.chapters.count,
                    total: document.chapters.count,
                    fraction: 1
                )
                try? projects.writeArtifact(report, name: "book-analysis", projectID: project.id)
                persistCurrent()
                showToast("一键拆书完成")
            } catch is CancellationError {
                bookProgress.detail = "拆书任务已取消"
            } catch {
                present(error)
            }
            isRunning = false
            activeTask = nil
        }
    }

    func reviseBookAnalysis(instruction: String) {
        guard let report = project.bookAnalysis else { return present(PipelineError.noBookAnalysis) }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = KeychainStore.load() ?? ""
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
                    apiKey: key
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
                showToast("拆书报告已按指令更新")
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
        activeTab = .outline
        primaryView = .studio
        pipelineProgress = PipelineProgress()
        bookProgress = BookAnalysisProgress()
        UserDefaults.standard.removeObject(forKey: "currentProjectID")
        showToast("已新建空白项目")
    }

    func resetToHome() {
        if project.hasContent { persistCurrent() }
        newProject()
        showToast("已重置到初始首页；原项目保留在项目档案")
    }

    func openProject(_ value: StoredProject) {
        if project.hasContent { persistCurrent() }
        project = value
        selectedChapter = 0
        selectedEpisode = 0
        primaryView = .studio
        activeTab = value.result == nil ? .outline : .script
        UserDefaults.standard.set(value.id.uuidString, forKey: "currentProjectID")
    }

    func duplicateProject(_ value: StoredProject) {
        do {
            let (copy, library) = try projects.duplicate(value)
            projectLibrary = library
            openProject(copy)
            showToast("项目副本已创建")
        } catch { present(error) }
    }

    func archiveProject(_ value: StoredProject) {
        do {
            projectLibrary = try projects.archive(value)
            if value.id == project.id { newProject() }
            showToast("项目已归档")
        } catch { present(error) }
    }

    func restoreProject(_ value: StoredProject) {
        do {
            projectLibrary = try projects.restore(value)
            if let restored = projectLibrary.first(where: { $0.id == value.id }) {
                openProject(restored)
            }
            showToast("项目已恢复到最近项目")
        } catch { present(error) }
    }

    func requestDelete(_ value: StoredProject) { pendingDelete = value }

    func confirmDelete() {
        guard let value = pendingDelete else { return }
        do {
            projectLibrary = try projects.delete(value)
            pendingDelete = nil
            if value.id == project.id { newProject() }
            showToast("项目已永久删除")
        } catch { present(error) }
    }

    func updateProjectName(_ name: String) {
        project.name = name
        persistCurrent()
    }

    func updateOptions(_ mutate: (inout AdaptationOptions) -> Void) {
        mutate(&project.options)
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
            showToast("提示词已恢复默认")
        } catch { present(error) }
    }

    func saveSettings(_ settings: ModelSettings, apiKey: String, consentGranted: Bool) {
        var updated = settings
        updated.consentedEndpointHost = consentGranted ? updated.endpointHost : ""
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { try KeychainStore.save(apiKey: trimmed) }
            modelSettings = updated
            Self.persistModelSettings(updated)
            showSettings = false
            showToast("模型连接已保存")
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

    func exportBookAnalysis() {
        guard let report = project.bookAnalysis else { return present(PipelineError.noBookAnalysis) }
        saveText(
            BookAnalysisPipeline.renderMarkdown(report),
            suggestedName: "\(report.title)·拆书报告",
            type: .markdown
        )
    }

    private func generateNamesIfAvailable() {
        guard
            let document = project.document,
            modelSettings.useOnline,
            modelSettings.hasEndpointConsent,
            let key = KeychainStore.load(),
            !key.isEmpty,
            !project.characters.isEmpty
        else {
            project.characters = CharacterExtractor.resolveModelNames(
                characters: project.characters,
                proposals: []
            )
            project.phase = .idle
            persistCurrent()
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
                    detail: "人物新名已由高速模型生成，可继续手动修改",
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
                pipelineProgress.detail = "高速命名不可用，已使用无占位名的本地安全候选"
                persistCurrent()
                showToast("人物命名已使用本地安全候选，可手动修改")
            }
        }
    }

    private func persistCurrent() {
        guard project.hasContent else { return }
        project.updatedAt = Date()
        do {
            projectLibrary = try projects.save(project)
            if let saved = projectLibrary.first(where: { $0.id == project.id }) {
                project = saved
            }
            UserDefaults.standard.set(project.id.uuidString, forKey: "currentProjectID")
        } catch { presentedError = error.localizedDescription }
    }

    private func saveText(_ value: String, suggestedName: String, type: UTType) {
        let panel = NSSavePanel()
        panel.title = "导出文件"
        panel.nameFieldStringValue = "\(safeFileName(suggestedName)).\(type == .markdown ? "md" : "txt")"
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try value.write(to: url, atomically: true, encoding: .utf8)
            showToast("文件已导出")
        } catch { present(error) }
    }

    private func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[\\/:*?\"<>|]"#,
            with: "_",
            options: .regularExpression
        )
    }

    private func present(_ error: Error) { presentedError = error.localizedDescription }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }

    private static func loadModelSettings() -> ModelSettings {
        guard
            let data = UserDefaults.standard.data(forKey: "modelSettings.v2"),
            let settings = try? JSONDecoder.scriptForge.decode(ModelSettings.self, from: data)
        else { return ModelSettings() }
        return settings
    }

    private static func persistModelSettings(_ settings: ModelSettings) {
        guard let data = try? JSONEncoder.scriptForge.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "modelSettings.v2")
    }

    private static func inputHash(_ document: NovelDocument) -> String {
        "\(document.characterCount)-\(document.chapters.count)-\(document.title.hashValue)"
    }

    private static let offlineSteps: [(PipelinePhase, String, Double)] = [
        (.analysis, "正在抽取故事事实、冲突和情绪爆点", 0.2),
        (.bible, "正在建立人物关系、世界规则和时间线", 0.38),
        (.outline, "正在重组分集目标、反转与动态场次", 0.55),
        (.drafting, "正在生成场景动作和角色对白", 0.76),
        (.quality, "正在检查旧名、时长、连续性与钩子", 0.92),
    ]
}

enum StudioTab: String, CaseIterable, Identifiable, Hashable {
    case outline
    case bible
    case script
    case quality

    var id: String { rawValue }
}
