import XCTest
@testable import ScriptForgeMac

final class CharacterExtractorTests: XCTestCase {
    func testFallbackNeverProducesGenericRoleNames() throws {
        let text = Array(repeating: "程青看向东雪瑶。东雪瑶问程青为何回来。董修远拦住程青。", count: 20)
            .joined(separator: "\n")
        let document = try NovelParser.parse(text: text, fileName: "cast.txt")
        let characters = CharacterExtractor.extract(from: document, limit: 12)
        let resolved = CharacterExtractor.resolveModelNames(characters: characters, proposals: [])
        XCTAssertFalse(resolved.isEmpty)
        XCTAssertTrue(resolved.allSatisfy { !CharacterExtractor.isGenericName($0.targetName) })
        XCTAssertEqual(Set(resolved.map(\.targetName)).count, resolved.count)
        XCTAssertTrue(CharacterExtractor.validate(resolved))
    }

    func testInvalidModelProposalsUseSafeUniqueFallbacks() throws {
        let source = [
            CharacterProfile(id: "1", sourceName: "程青", targetName: "程野", role: "主角", traits: [], occurrences: 8, locked: false, nameSource: .local),
            CharacterProfile(id: "2", sourceName: "东雪瑶", targetName: "沈知夏", role: "主要角色", traits: [], occurrences: 6, locked: false, nameSource: .local),
        ]
        let result = CharacterExtractor.resolveModelNames(
            characters: source,
            proposals: [
                .init(sourceName: "程青", targetName: "角色8"),
                .init(sourceName: "东雪瑶", targetName: "角色8"),
            ]
        )
        XCTAssertEqual(Set(result.map(\.targetName)).count, 2)
        XCTAssertFalse(result.contains { CharacterExtractor.isGenericName($0.targetName) })
    }
}
