import XCTest
@testable import ScriptForgeMac

final class ScreenplayPipelineTests: XCTestCase {
    func testPrivateScreenplayAcceptanceWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["SCRIPT_FORGE_ACCEPTANCE_FILE"],
              FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Set SCRIPT_FORGE_ACCEPTANCE_FILE to run the private screenplay acceptance fixture")
        }
        let document = try DocumentImporter.load(from: URL(fileURLWithPath: path))
        guard document.resolvedSourceKind == .screenplay else {
            throw XCTSkip("Private fixture is prose, not an existing screenplay")
        }
        let characters = ScreenplayPipeline.characters(from: document)
        var options = AdaptationOptions()
        options.episodeCount = document.chapters.count
        options.durationSeconds = 60

        let result = try ScreenplayPipeline.run(
            document: document,
            characters: characters,
            options: options
        )
        let package = StoryboardPipeline.runOffline(
            result: result,
            characters: characters,
            durationSeconds: options.durationSeconds
        )

        XCTAssertEqual(result.episodes.count, document.chapters.count)
        XCTAssertEqual(result.episodes.map(\.number), document.chapters.map(\.index))
        XCTAssertTrue(result.episodes.allSatisfy { !$0.scenes.isEmpty })
        XCTAssertEqual(package.episodes.count, result.episodes.count)
        XCTAssertTrue(package.episodes.allSatisfy {
            abs($0.totalDurationSeconds - Double(options.durationSeconds)) < 0.000_001
        })
        XCTAssertTrue(package.episodes.flatMap(\.shots).allSatisfy {
            !$0.imagePrompt.isEmpty && $0.imagePrompt.contains("9:16")
        })
        print(
            "PRIVATE_SCREENPLAY units=\(document.chapters.count) " +
            "scenes=\(result.episodes.reduce(0) { $0 + $1.scenes.count }) " +
            "characters=\(characters.count) shots=\(package.shotCount)"
        )
    }

    func testExistingScriptPassesThroughWithoutRenamingOrRewriting() throws {
        let text = """
        第1集：归来
        关键词：旧宅、真相
        人物：程野、沈知夏
        场次1：旧宅门厅
        【画面】程野推开积灰的大门，沈知夏守在台阶下。
        【对白】
        程野：灯还亮着。
        沈知夏：里面有人。
        【钩子】二楼突然传来脚步声。

        第2集：来客
        人物：程野、沈知夏、顾川
        内景 客厅 - 夜
        顾川：你们来晚了。
        程野：真相还在这里。
        """
        let document = try NovelParser.parse(text: text, fileName: "script.txt")
        let characters = ScreenplayPipeline.characters(from: document)
        var options = AdaptationOptions()
        options.episodeCount = 99

        let result = try ScreenplayPipeline.run(
            document: document,
            characters: characters,
            options: options
        )

        XCTAssertEqual(characters.map(\.sourceName), characters.map(\.targetName))
        XCTAssertEqual(result.episodes.map(\.number), [1, 2])
        XCTAssertEqual(result.episodes[0].scenes.count, 1)
        XCTAssertEqual(result.episodes[0].scenes[0].dialogue.count, 2)
        XCTAssertTrue(result.episodes[0].content.contains("程野：灯还亮着。"))
        XCTAssertEqual(result.episodes[0].endHook, "二楼突然传来脚步声。")
        XCTAssertEqual(result.storyBible.worldRules.first?.fact, "人物、事件、设定、对白与结局以导入原稿为准")
    }
}
