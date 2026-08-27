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
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let document = DocumentImporter.supportedExtensions.contains(url.pathExtension.lowercased())
            ? try DocumentImporter.load(from: url)
            : try NovelParser.parse(data: data, fileName: url.lastPathComponent)
        XCTAssertGreaterThanOrEqual(document.chapters.count, 10)
        XCTAssertGreaterThan(document.characterCount, 10_000)
        if url.pathExtension.lowercased() != "docx" {
            XCTAssertEqual(document.rawText.count, try DocumentImporter.decodePlainText(data).trimmingCharacters(in: .whitespacesAndNewlines).count)
        }
    }

    func testDetectsScreenplayStructureAndReportsSequenceGaps() throws {
        let text = """
        第1集：开端
        场次1：车站
        【画面】雨夜，顾川站在站台尽头。
        【对白】
        顾川：你终于来了。
        【钩子】远处列车突然熄灯。

        第3集：追踪
        场次1：仓库
        【画面】沈知夏推开生锈铁门。
        沈知夏：里面有人。
        """

        let document = try NovelParser.parse(text: text, fileName: "script.txt")

        XCTAssertEqual(document.resolvedSourceKind, .screenplay)
        XCTAssertEqual(document.chapters.map(\.index), [1, 3])
        XCTAssertEqual(document.chapters.map(\.title), ["开端", "追踪"])
        XCTAssertTrue(document.sourceDiagnostics.contains {
            $0.code == "screenplay.missing_episode_numbers" && $0.unitNumbers == [2]
        })
    }

    func testEnglishEpisodeAndSceneSyntaxIsFormatAgnostic() throws {
        let text = """
        EPISODE 01 - Arrival
        SCENE 1 - Platform
        [ACTION]
        Rain sweeps across the empty station.
        [DIALOGUE]
        MAYA: We are late.

        EP 02: Signal
        INT. CONTROL ROOM - NIGHT
        NOAH: The signal is gone.
        """

        let document = try NovelParser.parse(text: text, fileName: "pilot.md")

        XCTAssertEqual(document.resolvedSourceKind, .screenplay)
        XCTAssertEqual(document.chapters.count, 2)
        XCTAssertEqual(document.chapters.map(\.index), [1, 2])
    }

    func testMarkdownChapterHeadingsAreSplitWithoutKeepingHeadingMarkup() throws {
        let text = """
        # The Lantern Keeper

        ## Chapter 1: The Last Ferry
        Mara reached the pier before midnight.

        ### CHAPTER 2 - A Light Across the Water
        A pale lantern moved on the opposite shore.

        ## Chapter 3
        The ferryman finally spoke.
        """

        let document = try NovelParser.parse(text: text, fileName: "lantern.md")

        XCTAssertEqual(document.chapters.count, 3)
        XCTAssertEqual(document.chapters.map(\.index), [1, 2, 3])
        XCTAssertEqual(document.chapters.map(\.title), [
            "The Last Ferry",
            "A Light Across the Water",
            "Chapter 3",
        ])
        XCTAssertFalse(document.chapters[0].content.contains("## Chapter"))
        XCTAssertTrue(document.chapters[2].content.contains("ferryman"))
    }

    func testEpisodeLabeledProseWithoutScreenplaySignalsRemainsProse() throws {
        let text = """
        第1集 初见
        雨停以后，她沿着山路走了很久，回忆起故乡的一切。

        第2集 回家
        天亮时，她终于看见旧屋的灯。
        """

        let document = try NovelParser.parse(text: text, fileName: "serial.txt")

        XCTAssertEqual(document.resolvedSourceKind, .prose)
        XCTAssertEqual(document.chapters.count, 2)
    }

    func testUnsegmentedIndustryScreenplayBecomesSingleScriptUnit() throws {
        let text = """
        INT. KITCHEN - NIGHT
        MAYA: Did you hear that?
        NOAH: It came from upstairs.

        EXT. HOUSE - CONTINUOUS
        MAYA: The window is open.
        NOAH: Stay behind me.
        """

        let document = try NovelParser.parse(text: text, fileName: "feature.txt")

        XCTAssertEqual(document.resolvedSourceKind, .screenplay)
        XCTAssertEqual(document.chapters.count, 1)
        XCTAssertEqual(document.chapters[0].title, "Main Text")
        XCTAssertTrue(document.sourceDiagnostics.contains { $0.code == "screenplay.single_unit" })
    }

    func testLegacyDocumentWithoutClassificationDefaultsToProse() throws {
        let data = Data("""
        {
          "fileName": "legacy.txt",
          "title": "旧项目",
          "author": "",
          "intro": "",
          "rawText": "正文",
          "characterCount": 2,
          "chapters": [
            {"id":"chapter-1","index":1,"title":"正文","content":"正文","characterCount":2}
          ]
        }
        """.utf8)

        let document = try JSONDecoder.scriptForge.decode(NovelDocument.self, from: data)

        XCTAssertEqual(document.resolvedSourceKind, .prose)
        XCTAssertTrue(document.sourceDiagnostics.isEmpty)
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
