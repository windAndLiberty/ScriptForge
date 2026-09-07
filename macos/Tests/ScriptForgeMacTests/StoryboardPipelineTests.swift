import XCTest
@testable import ScriptForgeMac

final class StoryboardPipelineTests: XCTestCase {
    func testOfflineStoryboardProducesTimedShotsAndStableVisualPrompts() throws {
        let document = NovelDocument(
            fileName: "story.txt",
            title: "归来",
            author: "",
            intro: "林原回到故乡寻找真相。",
            rawText: "第一章 归来\n林原推开旧宅的门。苏禾问他为何回来。",
            characterCount: 24,
            chapters: [
                Chapter(
                    id: "chapter-1",
                    index: 1,
                    title: "归来",
                    content: "林原推开旧宅的门。苏禾问他为何回来。",
                    characterCount: 20
                ),
            ]
        )
        let characters = [
            CharacterProfile(
                id: "c1",
                sourceName: "林原",
                targetName: "程野",
                role: "男主",
                traits: ["克制", "警觉"],
                occurrences: 5,
                locked: true,
                nameSource: .manual
            ),
            CharacterProfile(
                id: "c2",
                sourceName: "苏禾",
                targetName: "沈知夏",
                role: "盟友",
                traits: ["冷静", "敏锐"],
                occurrences: 3,
                locked: true,
                nameSource: .manual
            ),
        ]
        var options = AdaptationOptions()
        options.episodeCount = 3
        options.durationSeconds = 60
        let result = try OfflinePipeline.run(document: document, characters: characters, options: options)

        let package = StoryboardPipeline.runOffline(
            result: result,
            characters: characters,
            durationSeconds: 60
        )

        XCTAssertEqual(package.mode, .offline)
        XCTAssertEqual(package.episodes.count, 3)
        XCTAssertGreaterThan(package.shotCount, 3)
        for episode in package.episodes {
            XCTAssertEqual(episode.aspectRatio, "9:16")
            XCTAssertEqual(episode.totalDurationSeconds, 60, accuracy: 0.01)
            XCTAssertFalse(episode.characterVisualAnchors.isEmpty)
            XCTAssertTrue(episode.shots.allSatisfy { $0.imagePrompt.contains("9:16") })
            XCTAssertEqual(episode.shots.map(\.number), Array(1...episode.shots.count))
        }
    }

    func testLegacyModelSettingsKeepExistingConnectionWhenMediaFieldsAreMissing() throws {
        let data = Data("""
        {
          "baseURL": "https://example.test/v1",
          "primaryModel": "writer",
          "flashModel": "fast",
          "reasoningEffort": "medium",
          "useOnline": true,
          "consentedEndpointHost": "example.test"
        }
        """.utf8)

        let settings = try JSONDecoder.scriptForge.decode(ModelSettings.self, from: data)

        XCTAssertEqual(settings.baseURL, "https://example.test/v1")
        XCTAssertEqual(settings.primaryModel, "writer")
        XCTAssertEqual(settings.imageModel, "")
        XCTAssertEqual(settings.speechModel, "")
        XCTAssertEqual(settings.speechVoice, "alloy")
        XCTAssertTrue(settings.hasEndpointConsent)
    }

    func testDenseStoryboardDurationsAlwaysSumExactlyToTarget() throws {
        let document = try NovelParser.parse(
            text: "第一章 归来\n程青回到旧宅，沈知夏跟在身后。",
            fileName: "dense.txt"
        )
        let extracted = CharacterExtractor.extract(from: document)
        let characters = CharacterExtractor.resolveModelNames(characters: extracted, proposals: [])
        var options = AdaptationOptions()
        options.episodeCount = 1
        options.durationSeconds = 60
        var result = try OfflinePipeline.run(
            document: document,
            characters: characters,
            options: options
        )
        let speakers = characters.isEmpty ? ["程野", "沈知夏"] : characters.map(\.targetName)
        result.episodes[0].scenes = (1...3).map { scene in
            ScriptScene(
                id: "dense-scene-\(scene)",
                heading: "内景 测试场景 - 夜",
                location: "测试场景",
                action: "人物完成连续动作并观察对手反应。",
                dialogue: (1...7).map { line in
                    DialogueLine(
                        speaker: speakers[line % speakers.count],
                        text: "这是第\(line)句用于时长配平的短对白。"
                    )
                }
            )
        }

        let package = StoryboardPipeline.runOffline(
            result: result,
            characters: characters,
            durationSeconds: 60
        )

        XCTAssertEqual(package.episodes[0].shots.count, 24)
        XCTAssertEqual(package.episodes[0].totalDurationSeconds, 60, accuracy: 0.000_001)
        XCTAssertTrue(package.episodes[0].shots.allSatisfy { $0.durationSeconds >= 0.5 })
    }

    func testStoryboardPromptsOnlyIncludeCharactersPresentInTheScene() throws {
        let document = try NovelParser.parse(
            text: "第一章 归来\n林原独自走进旧宅。",
            fileName: "focused-cast.txt"
        )
        let characters = [
            CharacterProfile(
                id: "c1",
                sourceName: "林原",
                targetName: "程野",
                role: "主角",
                traits: ["短发", "深色风衣"],
                occurrences: 4,
                locked: true,
                nameSource: .manual
            ),
            CharacterProfile(
                id: "c2",
                sourceName: "苏禾",
                targetName: "沈知夏",
                role: "盟友",
                traits: ["长发", "浅色外套"],
                occurrences: 2,
                locked: true,
                nameSource: .manual
            ),
        ]
        var options = AdaptationOptions()
        options.episodeCount = 1
        options.durationSeconds = 60
        var result = try OfflinePipeline.run(
            document: document,
            characters: characters,
            options: options
        )
        result.episodes[0].content = "程野独自走进旧宅。"
        result.episodes[0].scenes = [
            ScriptScene(
                id: "focused-scene",
                heading: "内景 旧宅 - 夜",
                location: "旧宅",
                action: "程野独自检查房间。",
                dialogue: []
            ),
        ]

        let episode = StoryboardPipeline.runOffline(
            result: result,
            characters: characters,
            durationSeconds: 60
        ).episodes[0]

        XCTAssertEqual(episode.characterVisualAnchors.count, 1)
        XCTAssertTrue(episode.characterVisualAnchors[0].contains("程野"))
        XCTAssertTrue(episode.shots.allSatisfy { $0.imagePrompt.contains("程野") })
        XCTAssertTrue(episode.shots.allSatisfy { !$0.imagePrompt.contains("沈知夏") })
    }
}
