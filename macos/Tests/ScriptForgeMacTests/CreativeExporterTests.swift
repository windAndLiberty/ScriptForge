import Foundation
import XCTest
@testable import ScriptForgeMac

final class CreativeExporterTests: XCTestCase {
    func testAcceptedChaptersExportToMarkdownJSONAndRoundTripDOCX() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)
        var project = StoredProject(name: "长夜归途")
        let chapterID = UUID()
        let versionID = UUID()
        let content = "程野推开旧宅的门。\n\n屋内传来陌生的脚步声。"
        let path = try repository.writeChapterVersion(
            content,
            chapterID: chapterID,
            versionID: versionID,
            projectID: project.id
        )
        var workspace = CreativeWorkspace()
        workspace.outlines = [VolumeOutline(
            id: UUID(),
            number: 1,
            title: "第一卷 归来",
            arcSummary: "寻找真相",
            chapterCards: [],
            createdAt: Date()
        )]
        workspace.chapters = [ChapterDocument(
            id: chapterID,
            number: 1,
            volumeNumber: 1,
            title: "旧宅",
            cardID: nil,
            status: .accepted,
            currentVersionID: versionID,
            candidateVersionID: nil,
            versions: [ChapterVersion(
                id: versionID,
                createdAt: Date(),
                source: .manual,
                contentPath: path,
                summary: "归来",
                wordCount: content.count,
                promptSnapshotID: nil,
                accepted: true
            )]
        )]
        project.creativeWorkspace = workspace

        let export = try CreativeExporter.makeExport(project: project, repository: repository)
        let markdown = CreativeExporter.markdown(export)
        let json = try CreativeExporter.json(export)
        let docx = try CreativeExporter.docx(export)

        XCTAssertTrue(markdown.contains("## 第一卷 归来"))
        XCTAssertTrue(markdown.contains("### 第1章 旧宅"))
        XCTAssertNoThrow(try JSONDecoder.scriptForge.decode(CreativeProjectExport.self, from: json))

        let docxURL = root.appendingPathComponent("roundtrip.docx")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try docx.write(to: docxURL)
        let imported = try DocumentImporter.load(from: docxURL)
        XCTAssertTrue(imported.rawText.contains("第一卷 归来"))
        XCTAssertTrue(imported.rawText.contains("第1章 旧宅"))
        XCTAssertTrue(imported.rawText.contains("屋内传来陌生的脚步声。"))
    }
}
