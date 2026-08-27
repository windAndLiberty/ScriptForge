import XCTest
@testable import ScriptForgeMac

final class OfflinePipelineTests: XCTestCase {
    func testOfflinePipelineProducesDynamicScenesAndNoOldNames() throws {
        let text = Array(repeating: "程青从天渊归来。东雪瑶看见程青，董修远拦住众人。", count: 40)
            .joined(separator: "\n")
        let document = try NovelParser.parse(text: text, fileName: "novel.txt")
        let extracted = CharacterExtractor.extract(from: document)
        let characters = CharacterExtractor.resolveModelNames(characters: extracted, proposals: [])
        var options = AdaptationOptions()
        options.episodeCount = 3
        options.durationSeconds = 60

        let result = try OfflinePipeline.run(document: document, characters: characters, options: options)
        XCTAssertEqual(result.episodes.count, 3)
        XCTAssertTrue(result.episodes.allSatisfy { (1...3).contains($0.scenes.count) })
        XCTAssertTrue(result.episodes.allSatisfy { $0.runtime != nil })
        for character in characters {
            XCTAssertFalse(result.episodes.map(\.content).joined().contains(character.sourceName))
            XCTAssertFalse(CharacterExtractor.isGenericName(character.targetName))
        }
    }

    func testEnglishSourceStaysEnglishAndMeetsEpisodeWordBudget() throws {
        let text = Array(repeating: "Mara finds a sealed ledger in the harbor archive while Elias blocks Victor from taking it.", count: 30)
            .joined(separator: "\n")
        let document = try NovelParser.parse(text: text, fileName: "harbor.txt")
        var options = AdaptationOptions()
        options.episodeCount = 2
        options.durationSeconds = 60

        let result = try OfflinePipeline.run(document: document, characters: [], options: options)
        let rendered = result.episodes.map(\.content).joined(separator: "\n")
        let qualityText = result.quality.metrics.map { $0.label + $0.detail }.joined()
            + result.quality.warnings.joined()

        XCTAssertEqual(options.outputLanguage(for: document), .english)
        XCTAssertEqual(result.genre, "Fantasy Comeback")
        XCTAssertTrue(result.episodes.allSatisfy {
            EpisodeBudget.assess(
                scenes: $0.scenes,
                durationSeconds: 60,
                language: .english
            ).runtime.spokenCharacters >= 105
        })
        XCTAssertNil((rendered + qualityText).range(
            of: #"[\u3400-\u4DBF\u4E00-\u9FFF]"#,
            options: .regularExpression
        ))
    }
}
