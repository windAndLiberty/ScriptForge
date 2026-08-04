import XCTest
@testable import ScriptForgeMac

final class EpisodeBudgetTests: XCTestCase {
    func testSixtySecondSceneCountIsDynamicRange() {
        XCTAssertEqual(EpisodeBudget.sceneRange(durationSeconds: 60), 1...3)
        let budget = EpisodeBudget.budget(durationSeconds: 60)
        XCTAssertEqual(budget.dialogueLines, 12...18)
        XCTAssertEqual(budget.spokenCharacters, 129...195)
    }

    func testCompletenessUsesWholeEpisodeNotPerSceneMinimum() {
        let dialogue = (1...14).map {
            DialogueLine(speaker: $0.isMultiple(of: 2) ? "程野" : "沈知夏", text: "这不是巧合，真相就在眼前")
        }
        let scene = ScriptScene(
            id: "s1",
            heading: "内景 大殿 - 日",
            location: "魂灯在众人面前突然变黑",
            action: "程野按住魂灯，火焰沿着掌心逆流；沈知夏挡住冲来的守卫，众人同时后退。",
            dialogue: dialogue
        )
        let result = EpisodeBudget.assess(scenes: [scene], durationSeconds: 60)
        XCTAssertGreaterThanOrEqual(result.runtime.dialogueLines, 12)
        XCTAssertFalse(result.issues.contains { $0.contains("每场至少") })
    }
}
