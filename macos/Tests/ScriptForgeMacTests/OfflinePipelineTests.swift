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
}
