import Foundation
import XCTest
@testable import ScriptForgeMac

final class ScriptForgeBusinessSmokeTests: XCTestCase {
    @MainActor
    func testDroppedEnglishManuscriptImportsPersistsAndCompletesLocalBookAnalysis() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let sourceURL = try writeEnglishManuscript(to: harness.root)
        harness.defaults.set(AppLanguage.english.rawValue, forKey: "uiLanguage")
        let model = harness.makeModel()

        XCTAssertTrue(model.importDroppedFiles([sourceURL], route: .adaptation))
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.primaryView, .studio)
        XCTAssertEqual(model.project.document?.resolvedSourceKind, .prose)
        XCTAssertEqual(model.project.document?.chapters.count, 3)
        XCTAssertEqual(model.project.options.episodeCount, 3)
        XCTAssertTrue(harness.repository.loadAll().contains { $0.id == model.project.id })

        model.runBookAnalysis()
        for _ in 0..<100 where model.isRunning {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertFalse(model.isRunning)
        let report = try XCTUnwrap(model.project.bookAnalysis)
        XCTAssertEqual(report.outputLanguage, .english)
        XCTAssertEqual(report.sections.map(\.title), [
            "Content Overview",
            "Structure and Pacing",
            "Character System",
            "Commercial Highlights",
            "Language and Style",
            "Reusable Techniques",
        ])
        let renderedReport = BookAnalysisPipeline.renderMarkdown(report)
        XCTAssertTrue(renderedReport.contains("Book Analysis Report"))
        XCTAssertFalse(renderedReport.contains("拆书报告"))
        XCTAssertFalse(renderedReport.contains("本地模式"))
        XCTAssertNil(renderedReport.range(
            of: #"[\u3400-\u4DBF\u4E00-\u9FFF]"#,
            options: .regularExpression
        ))
        XCTAssertTrue(model.bookProgress.detail.contains("Book analysis complete"))
        XCTAssertTrue(harness.repository.loadAll().contains {
            $0.id == model.project.id && $0.bookAnalysis != nil
        })
    }

    @MainActor
    func testDroppedEnglishManuscriptCreatesEditableCreativeWorkspace() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let sourceURL = try writeEnglishManuscript(to: harness.root)
        let model = harness.makeModel()

        XCTAssertTrue(model.importDroppedFiles([sourceURL], route: .creation))
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.primaryView, .creation)
        XCTAssertEqual(model.project.document?.chapters.count, 3)
        XCTAssertEqual(model.project.creativeWorkspace?.chapters.count, 3)
        XCTAssertNotNil(model.selectedCreativeChapterID)
        XCTAssertFalse(model.creativeEditorText.isEmpty)
        XCTAssertTrue(harness.repository.loadAll().contains {
            $0.id == model.project.id && $0.creativeWorkspace?.chapters.count == 3
        })
    }

    private func makeHarness() throws -> SmokeHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "ScriptForgeSmoke.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return SmokeHarness(root: root, suiteName: suiteName, defaults: defaults)
    }

    private func writeEnglishManuscript(to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("The Quiet Harbor.md")
        let manuscript = """
        # The Quiet Harbor

        CHAPTER 1 - The Letter
        Mara found Evelyn's letter beneath a blue cup. Rain touched the windows while Jonah waited at the gate.

        CHAPTER 2 - The Pier
        Mara and Jonah walked to the broken pier. They chose one board to repair before sunset.

        CHAPTER 3 - Open Water
        The ferry crossed the harbor wall. Mara kept the old letter and allowed the town to remain in view.
        """
        try manuscript.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private struct SmokeHarness {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let repository: ProjectRepository

    init(root: URL, suiteName: String, defaults: UserDefaults) {
        self.root = root
        self.suiteName = suiteName
        self.defaults = defaults
        repository = ProjectRepository(baseURL: root.appendingPathComponent("repository"))
    }

    @MainActor
    func makeModel() -> AppModel {
        let settings = ModelSettings()
        return AppModel(
            projectRepository: repository,
            promptRepository: PromptAssetRepository(baseURL: root.appendingPathComponent("prompts")),
            creativePromptRepository: CreativePromptRepository(baseURL: root.appendingPathComponent("creative-prompts")),
            modelSettingsOverride: settings,
            userDefaults: defaults
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
