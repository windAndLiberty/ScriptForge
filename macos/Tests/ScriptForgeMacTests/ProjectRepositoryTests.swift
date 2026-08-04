import XCTest
@testable import ScriptForgeMac

final class ProjectRepositoryTests: XCTestCase {
    func testRecentOverflowArchivesWithoutDeleting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)

        for index in 0...ProjectRepository.recentLimit {
            var project = StoredProject(name: "项目\(index)")
            project.document = fixtureDocument(index: index)
            _ = try repository.save(project)
        }
        let all = repository.loadAll()
        XCTAssertEqual(all.count, ProjectRepository.recentLimit + 1)
        XCTAssertEqual(all.filter { $0.archivedAt == nil }.count, ProjectRepository.recentLimit)
        XCTAssertEqual(all.filter { $0.archivedAt != nil }.count, 1)
    }

    func testOnlyArchivedProjectCanBeDeleted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptForgeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(baseURL: root)
        var project = StoredProject(name: "待删除")
        project.document = fixtureDocument(index: 1)
        _ = try repository.save(project)
        XCTAssertThrowsError(try repository.delete(project))
        let archived = try XCTUnwrap(repository.archive(project).first { $0.id == project.id })
        let remaining = try repository.delete(archived)
        XCTAssertFalse(remaining.contains { $0.id == project.id })
    }

    private func fixtureDocument(index: Int) -> NovelDocument {
        NovelDocument(
            fileName: "\(index).txt",
            title: "小说\(index)",
            author: "作者",
            intro: "简介",
            rawText: "第一章 测试\n正文",
            characterCount: 6,
            chapters: [Chapter(id: "chapter-1", index: 1, title: "测试", content: "正文", characterCount: 2)]
        )
    }
}
