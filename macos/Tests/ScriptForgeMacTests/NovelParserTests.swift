import XCTest
@testable import ScriptForgeMac

final class NovelParserTests: XCTestCase {
    func testParsesChineseChapterBoundariesWithoutTruncation() throws {
        let text = """
        《测试小说》
        作者：剧擎

        第一章 归来
        程青从天渊走出。董修远看见了他。

        第二章 魂灯
        魂灯突然燃烧。程青发现一道陌生剑气。
        """
        let document = try NovelParser.parse(text: text, fileName: "fixture.txt")
        XCTAssertEqual(document.title, "测试小说")
        XCTAssertEqual(document.author, "剧擎")
        XCTAssertEqual(document.chapters.count, 2)
        XCTAssertTrue(document.chapters[1].content.contains("陌生剑气"))
        XCTAssertEqual(document.rawText, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testAcceptanceAttachmentWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SCRIPT_FORGE_ACCEPTANCE_FILE"],
              FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Set SCRIPT_FORGE_ACCEPTANCE_FILE to run the private novel acceptance fixture")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let document = try NovelParser.parse(data: data, fileName: URL(fileURLWithPath: path).lastPathComponent)
        XCTAssertGreaterThanOrEqual(document.chapters.count, 10)
        XCTAssertGreaterThan(document.characterCount, 10_000)
        XCTAssertEqual(document.rawText.count, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    func testLongChapterIsSplitWithoutDroppingContent() throws {
        let content = String(repeating: "动作与对白。", count: 3_000)
        let chapter = Chapter(
            id: "chapter-1",
            index: 1,
            title: "长章",
            content: content,
            characterCount: content.count
        )
        let fragments = NovelParser.evidenceFragments(chapters: [chapter], maxCharacters: 2_000)
        XCTAssertGreaterThan(fragments.count, 1)
        XCTAssertEqual(fragments.map(\.content).joined(), content)
        XCTAssertTrue(fragments.allSatisfy { $0.id == chapter.id })
    }
}
