import Foundation
import XCTest
@testable import ScriptForgeMac

final class CreativeWorkspaceTests: XCTestCase {
    func testGeneratedDraftCreatesCandidateWithoutOverwritingAcceptedVersion() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)
        let projectID = UUID()
        let chapterID = UUID()
        let acceptedID = UUID()
        let acceptedPath = try repository.writeChapterVersion(
            "作者原稿",
            chapterID: chapterID,
            versionID: acceptedID,
            projectID: projectID
        )
        var workspace = CreativeWorkspace()
        workspace.chapters = [ChapterDocument(
            id: chapterID,
            number: 1,
            volumeNumber: 1,
            title: "归来",
            cardID: nil,
            status: .accepted,
            currentVersionID: acceptedID,
            candidateVersionID: nil,
            versions: [ChapterVersion(
                id: acceptedID,
                createdAt: Date(),
                source: .manual,
                contentPath: acceptedPath,
                summary: "原稿",
                wordCount: 4,
                promptSnapshotID: nil,
                accepted: true
            )]
        )]
        var input = WorkflowRunInput(batchCount: 1)
        input.selectedChapterIDs = [chapterID]
        var run = WorkflowEngine.start(workflowID: .chapterProduction, input: input)
        let payload = payload(content: "AI 候选稿")

        _ = try CreativeWorkspaceService.storePayload(
            payload,
            stepID: "draft",
            run: &run,
            workspace: &workspace,
            repository: repository,
            projectID: projectID
        )

        XCTAssertEqual(workspace.chapters[0].currentVersionID, acceptedID)
        XCTAssertNotNil(workspace.chapters[0].candidateVersionID)
        XCTAssertEqual(try repository.readCreativeText(relativePath: acceptedPath, projectID: projectID), "作者原稿")

        try CreativeWorkspaceService.acceptChapterCandidate(chapterID: chapterID, workspace: &workspace)

        XCTAssertNotEqual(workspace.chapters[0].currentVersionID, acceptedID)
        XCTAssertNil(workspace.chapters[0].candidateVersionID)
        XCTAssertEqual(workspace.chapters[0].versions.filter(\.accepted).count, 1)
    }

    func testRunningWorkflowIsRecoveredAsInterrupted() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)
        let projectID = UUID()
        var run = WorkflowEngine.start(workflowID: .incubation, input: WorkflowRunInput(seed: "灵感"))
        run.status = .running
        try repository.writeWorkflowRun(run, projectID: projectID)

        let loaded = try XCTUnwrap(repository.loadWorkflowRuns(projectID: projectID).first)

        XCTAssertEqual(loaded.status, .interrupted)
        XCTAssertEqual(repository.loadWorkflowRuns(projectID: projectID).first?.status, .interrupted)
    }

    func testV4ProjectWithoutCreativeWorkspaceDecodesAndUpgradesOnSave() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)
        var project = StoredProject(name: "旧项目")
        project.document = NovelDocument(
            fileName: "legacy.txt",
            title: "旧项目",
            author: "",
            intro: "",
            rawText: "第一章 开始\n正文",
            characterCount: 8,
            chapters: [Chapter(id: "1", index: 1, title: "开始", content: "正文", characterCount: 2)]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.scriptForge.encode(project)) as? [String: Any]
        )
        object["schemaVersion"] = 4
        object.removeValue(forKey: "creativeWorkspace")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.scriptForge.decode(StoredProject.self, from: legacy)

        XCTAssertNil(decoded.creativeWorkspace)
        _ = try repository.save(decoded)
        XCTAssertEqual(repository.loadAll().first?.schemaVersion, 5)
    }

    func testParagraphDiffReportsAddedAndRemovedParagraphs() {
        let entries = CreativeParagraphDiff.compare("第一段\n第二段", "第一段\n新第二段")
        XCTAssertTrue(entries.contains(where: { $0.kind == .removed && $0.text == "第二段" }))
        XCTAssertTrue(entries.contains(where: { $0.kind == .added && $0.text == "新第二段" }))
    }

    func testProjectDuplicationCarriesRunsAndChapterVersions() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)
        var project = StoredProject(name: "创作项目")
        let chapterID = UUID()
        let versionID = UUID()
        let path = try repository.writeChapterVersion(
            "第一章正文",
            chapterID: chapterID,
            versionID: versionID,
            projectID: project.id
        )
        var workspace = CreativeWorkspace()
        workspace.chapters = [ChapterDocument(
            id: chapterID,
            number: 1,
            volumeNumber: 1,
            title: "开始",
            cardID: nil,
            status: .accepted,
            currentVersionID: versionID,
            candidateVersionID: nil,
            versions: [ChapterVersion(
                id: versionID,
                createdAt: Date(),
                source: .manual,
                contentPath: path,
                summary: "开始",
                wordCount: 5,
                promptSnapshotID: nil,
                accepted: true
            )]
        )]
        project.creativeWorkspace = workspace
        _ = try repository.save(project)
        let run = WorkflowEngine.start(workflowID: .incubation, input: WorkflowRunInput(seed: "灵感"))
        try repository.writeWorkflowRun(run, projectID: project.id)

        let (copy, _) = try repository.duplicate(project)

        XCTAssertEqual(try repository.readCreativeText(relativePath: path, projectID: copy.id), "第一章正文")
        XCTAssertEqual(repository.loadWorkflowRuns(projectID: copy.id).first?.id, run.id)
    }

    private func payload(content: String) -> CreativeGenerationPayload {
        CreativeGenerationPayload(
            title: "第一章",
            summary: "候选摘要",
            markdown: content,
            items: [CreativeGenerationPayload.Item(
                kind: "chapter",
                name: "第一章",
                summary: "候选摘要",
                content: content,
                details: []
            )]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeCreative-\(UUID().uuidString)", isDirectory: true)
    }
}
