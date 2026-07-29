import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var project: ProjectState {
        didSet {
            saveProject()
        }
    }
    @Published var selectedChapter = 0
    @Published var selectedEpisode = 0
    @Published var activeTab = StudioTab.outline
    @Published var progress = 0.0
    @Published var progressDetail = ""
    @Published var isRunning = false
    @Published var presentedError: String?
    @Published var showSettings = false
    @Published var modelSettings: ModelSettings {
        didSet { saveModelSettings() }
    }

    init() {
        project = Self.loadProject() ?? ProjectState()
        modelSettings = Self.loadModelSettings()
    }

    var hasAPIKey: Bool {
        !(KeychainStore.load() ?? "").isEmpty
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
            let cast = CharacterExtractor.extract(from: document)
            project = ProjectState(
                name: "\(document.title)·短剧改编",
                document: document,
                characters: cast,
                options: AdaptationOptions(
                    episodeCount: min(12, max(4, document.chapters.count - 2))
                ),
                phase: .characters
            )
            selectedChapter = 0
            selectedEpisode = 0
            activeTab = .outline
            progress = 0.38
            progressDetail = "已拆解 \(document.chapters.count) 章并识别 \(cast.count) 位主要人物"
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func runPipeline() {
        guard let document = project.document else {
            presentedError = PipelineError.noDocument.localizedDescription
            return
        }
        guard CharacterExtractor.validate(project.characters) else {
            presentedError = PipelineError.invalidNames.localizedDescription
            return
        }

        isRunning = true
        activeTab = .outline
        Task {
            do {
                let result: AdaptationResult
                if modelSettings.useOnline {
                    guard let apiKey = KeychainStore.load(), !apiKey.isEmpty else {
                        throw PipelineError.missingAPIKey
                    }
                    result = try await OnlinePipeline.run(
                        document: document,
                        characters: project.characters,
                        options: project.options,
                        settings: modelSettings,
                        apiKey: apiKey
                    ) { [weak self] phase, detail, percent in
                        Task { @MainActor in
                            self?.project.phase = phase
                            self?.progressDetail = detail
                            self?.progress = percent
                        }
                    }
                } else {
                    let steps: [(PipelinePhase, String, Double)] = [
                        (.analysis, "正在抽取故事事实、冲突和情绪爆点", 0.22),
                        (.characters, "正在应用人物改名表并检查重名", 0.38),
                        (.outline, "正在重组分集目标、反转与卡点", 0.55),
                        (.drafting, "正在生成场景动作和角色对白", 0.76),
                        (.quality, "正在检查旧名、结构、钩子与内容风险", 0.92),
                    ]
                    for (phase, detail, percent) in steps {
                        project.phase = phase
                        progressDetail = detail
                        progress = percent
                        try await Task.sleep(for: .milliseconds(160))
                    }
                    result = try OfflinePipeline.run(
                        document: document,
                        characters: project.characters,
                        options: project.options
                    )
                }
                project.result = result
                project.phase = .completed
                progress = 1
                progressDetail = "已完成 \(result.episodes.count) 集，质检 \(result.quality.score) 分"
                selectedEpisode = 0
                activeTab = .script
            } catch {
                project.phase = .failed
                presentedError = error.localizedDescription
            }
            isRunning = false
        }
    }

    func exportScript() {
        guard let result = project.result else { return }
        let panel = NSSavePanel()
        panel.title = "导出短剧剧本"
        panel.nameFieldStringValue = "\(safeFileName(project.name)).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let output = [
            "《\(project.name)》",
            "题材：\(result.genre)",
            "规格：\(result.episodes.count)集 × 约\(project.options.durationSeconds)秒",
            "一句话梗概：\(result.logline)",
            "提示：AI辅助内容，须经编剧、制片与合规人员复核。",
            "",
            result.episodes.map(\.content).joined(separator: "\n\n"),
        ].joined(separator: "\n")
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func saveSettings(apiKey: String) {
        do {
            if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                try KeychainStore.save(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
            }
            saveModelSettings()
            showSettings = false
            objectWillChange.send()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func updateEpisodeContent(_ content: String) {
        guard
            var result = project.result,
            result.episodes.indices.contains(selectedEpisode)
        else { return }
        result.episodes[selectedEpisode].content = content
        project.result = result
    }

    private func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[\\/:*?"<>|]"#,
            with: "_",
            options: .regularExpression
        )
    }

    private func saveProject() {
        guard let url = Self.projectURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.scriptForge.encode(project)
            try data.write(to: url, options: .atomic)
        } catch {
            // Autosave errors remain non-blocking; explicit operations surface their own errors.
        }
    }

    private static func loadProject() -> ProjectState? {
        guard
            let url = projectURL,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder.scriptForge.decode(ProjectState.self, from: data)
    }

    private func saveModelSettings() {
        guard let data = try? JSONEncoder().encode(modelSettings) else { return }
        UserDefaults.standard.set(data, forKey: "modelSettings")
    }

    private static func loadModelSettings() -> ModelSettings {
        guard
            let data = UserDefaults.standard.data(forKey: "modelSettings"),
            let settings = try? JSONDecoder().decode(ModelSettings.self, from: data)
        else { return ModelSettings() }
        return settings
    }

    private static var projectURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("ScriptForge", isDirectory: true)
            .appendingPathComponent("project.json")
    }
}

enum StudioTab: String, CaseIterable, Identifiable {
    case outline
    case script
    case quality

    var id: String { rawValue }
}

private extension JSONEncoder {
    static var scriptForge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var scriptForge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
