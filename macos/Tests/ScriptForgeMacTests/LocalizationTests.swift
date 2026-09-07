import XCTest
@testable import ScriptForgeMac

final class LocalizationTests: XCTestCase {
    func testSourceLanguageDetectionUsesDominantWritingSystem() {
        XCTAssertEqual(AppLanguage.detect(in: "The river moved quietly beneath the old bridge."), .english)
        XCTAssertEqual(AppLanguage.detect(in: "河水从古桥下缓缓流过。"), .chinese)
    }

    func testAccessibilityScalingCopyIsAvailableInBothLanguages() {
        let pairs = [
            "无障碍访问": "Accessibility",
            "界面缩放": "Interface Scale",
            "放大": "Zoom In",
            "缩小": "Zoom Out",
            "实际大小": "Actual Size",
            "重置缩放": "Reset Zoom",
            "缩放级别": "Zoom Level",
            "视图": "View",
            "界面语言": "Interface Language",
        ]

        for (chinese, english) in pairs {
            XCTAssertEqual(LocalizationStore.text(chinese, language: .english), english)
            XCTAssertEqual(LocalizationStore.text(english, language: .chinese), chinese)
        }
    }

    func testLegacyAdaptationOptionsDefaultToPreservingSourceLanguage() throws {
        let data = Data(#"{"episodeCount":8,"durationSeconds":60,"genre":"Drama","tone":"Tense","trendPreset":"精品爽剧"}"#.utf8)
        let options = try JSONDecoder().decode(AdaptationOptions.self, from: data)

        XCTAssertTrue(options.preserveSourceLanguage)
        XCTAssertEqual(options.targetLanguage, .chinese)
    }

    func testLegacyGeneratedProjectNamesFollowInterfaceLanguage() {
        XCTAssertEqual(
            LocalizationStore.projectName(
                "ScriptForge-English-Literary-Sample·短剧改编",
                language: .english
            ),
            "ScriptForge-English-Literary-Sample · Short Drama Adaptation"
        )
        XCTAssertEqual(
            LocalizationStore.projectName(
                "ScriptForge-English-Literary-Sample · Short Drama Adaptation",
                language: .chinese
            ),
            "ScriptForge-English-Literary-Sample·短剧改编"
        )
    }

    func testStoredDefaultMetadataFollowsInterfaceLanguageWithoutChangingCustomValues() {
        let options = AdaptationOptions()
        XCTAssertEqual(options.resolvedGenre(for: .english), "Fantasy Comeback")
        XCTAssertEqual(
            options.resolvedTone(for: .english),
            "High-energy, restrained, with strong reversals"
        )
        XCTAssertEqual(LocalizationStore.documentUnitTitle("正文", language: .english), "Main Text")
        XCTAssertEqual(LocalizationStore.documentUnitTitle("第3章", language: .english), "Chapter 3")
        XCTAssertEqual(LocalizationStore.documentUnitTitle("Episode 2", language: .chinese), "第2集")

        var custom = options
        custom.genre = "Solarpunk Mystery"
        custom.tone = "Quiet and reflective"
        XCTAssertEqual(custom.resolvedGenre(for: .english), "Solarpunk Mystery")
        XCTAssertEqual(custom.resolvedTone(for: .chinese), "Quiet and reflective")
    }

    func testDynamicStatusAndErrorsCanBeRenderedInEnglish() {
        XCTAssertEqual(LocalizationStore.text("review", language: .english), "In Review")
        XCTAssertEqual(LocalizationStore.text("Current Character States", language: .chinese), "当前人物状态")
        XCTAssertEqual(
            LocalizationStore.errorText("模型 Base URL 无效", language: .english),
            "The model Base URL is invalid"
        )
        XCTAssertEqual(
            LocalizationStore.errorText("模型请求失败（HTTP 405）：Method Not Allowed", language: .english),
            "Model request failed (HTTP 405): Method Not Allowed"
        )
        XCTAssertEqual(
            LocalizationStore.errorText(
                "模型 JSON 结构不完整：$ 数据损坏：The given data was not valid JSON.",
                language: .english
            ),
            "Model JSON is incomplete: $ contains invalid data: The given data was not valid JSON."
        )
        XCTAssertEqual(
            LocalizationStore.errorText(
                "模型 JSON 结构不完整：未返回可见正文；推理可能耗尽完成预算 [finish_reason=length, completion_tokens=4096, reasoning_tokens=4096]",
                language: .english
            ),
            "Model JSON is incomplete: No visible content was returned; reasoning may have exhausted the completion budget [finish_reason=length, completion_tokens=4096, reasoning_tokens=4096]"
        )
        XCTAssertEqual(
            LocalizationStore.errorText(
                "PDF 中没有可提取的文字；扫描版 PDF 需要先进行 OCR",
                language: .english
            ),
            "No extractable text was found in the PDF. Scanned PDFs must be processed with OCR first"
        )
        XCTAssertEqual(
            LocalizationStore.errorText(
                "暂不支持 EPUB 格式；支持 DOCX、DOC、PDF、RTF、RTFD、TXT、Markdown、HTML 与 ODT",
                language: .english
            ),
            "EPUB format is not supported. Supported formats: DOCX, DOC, PDF, RTF, RTFD, TXT, Markdown, HTML, ODT"
        )
    }

    func testSwiftUIViewsDoNotRenderDirectChineseStringLiterals() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = ["Views.swift", "CreativeViews.swift"]
        let pattern = #"(?:Text|Button|Label|TextField|Toggle|Picker|DisclosureGroup)\(\s*\"[^\"\n]*[\u3400-\u4DBF\u4E00-\u9FFF]"#
        let expression = try NSRegularExpression(pattern: pattern)

        for file in files {
            let source = try String(
                contentsOf: root.appendingPathComponent("Sources/ScriptForgeMac/\(file)"),
                encoding: .utf8
            )
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            XCTAssertNil(expression.firstMatch(in: source, range: range), "Direct Chinese UI literal in \(file)")
        }
    }

    func testTopHintResolvesAgainstCurrentInterfaceLanguage() {
        let hint = LocalizedHint(
            chinese: "文件已导出",
            english: "File exported"
        )

        XCTAssertEqual(hint.text(for: .chinese), "文件已导出")
        XCTAssertEqual(hint.text(for: .english), "File exported")
    }

    @MainActor
    func testEnglishCountedUnitsUseCorrectPluralization() {
        let store = LocalizationStore()
        store.language = .english
        XCTAssertEqual(store.countedUnit("章节", count: 1), "chapter")
        XCTAssertEqual(store.countedUnit("章节", count: 2), "chapters")
        XCTAssertEqual(store.countedUnit("分集", count: 1), "episode")
        XCTAssertEqual(store.countedUnit("分集", count: 0), "episodes")
    }
}
