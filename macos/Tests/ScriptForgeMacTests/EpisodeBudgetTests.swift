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

    func testEnglishBudgetCountsWordsInsteadOfLetters() {
        let budget = EpisodeBudget.budget(durationSeconds: 60, language: .english)
        XCTAssertEqual(budget.spokenCharacters, 105...165)

        let line = "We cannot leave until the archive opens and everyone sees the ledger."
        let dialogue = (1...12).map {
            DialogueLine(speaker: $0.isMultiple(of: 2) ? "Mara" : "Elias", text: line)
        }
        let scene = ScriptScene(
            id: "english-scene",
            heading: "INT. ARCHIVE - NIGHT",
            location: "The sealed archive",
            action: "Mara breaks the wax seal while Elias blocks the only exit and the alarm begins to ring.",
            dialogue: dialogue
        )
        let result = EpisodeBudget.assess(
            scenes: [scene],
            durationSeconds: 60,
            language: .english
        )

        XCTAssertGreaterThanOrEqual(result.runtime.spokenCharacters, 105)
        XCTAssertTrue(result.passed)
    }

    func testEnglishRendererDoesNotInjectChineseLabels() {
        let episode = Episode(
            id: "episode-1",
            number: 1,
            title: "The Ledger",
            sourceChapterIDs: ["chapter-1"],
            plannedSceneCount: 1,
            openingHook: "The archive alarm rings.",
            objective: "Recover the ledger.",
            reversal: "The ledger is a forgery.",
            endHook: "The real author steps inside.",
            contract: EpisodeContract(
                dominantConflict: "Recover the ledger",
                newInformation: [],
                visualHook: "A broken seal",
                transitionFromPrevious: "Opening",
                activePropThreads: [],
                entryState: "Locked out",
                exitState: "Trapped inside"
            ),
            runtime: nil,
            semanticAudit: nil,
            scenes: [],
            content: ""
        )

        let rendered = OfflinePipeline.render(episode, language: .english)
        XCTAssertTrue(rendered.contains("EPISODE 1"))
        XCTAssertNil(rendered.range(
            of: #"[\u3400-\u4DBF\u4E00-\u9FFF]"#,
            options: .regularExpression
        ))
    }
}
