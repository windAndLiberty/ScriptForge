import XCTest
@testable import ScriptForgeMac

final class AccessibilitySettingsTests: XCTestCase {
    @MainActor
    func testPassiveConnectionStatusNeverLoadsTheKeychain() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scriptforge-passive-keychain-\(UUID().uuidString)")
        let suiteName = "ScriptForge.PassiveKeychain.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        var settings = ModelSettings()
        settings.useOnline = true
        settings.consentedEndpointHost = "api.openai.com"
        var keychainReadCount = 0
        let model = AppModel(
            projectRepository: ProjectRepository(baseURL: root.appendingPathComponent("projects")),
            promptRepository: PromptAssetRepository(baseURL: root.appendingPathComponent("prompts")),
            creativePromptRepository: CreativePromptRepository(baseURL: root.appendingPathComponent("creative-prompts")),
            modelSettingsOverride: settings,
            userDefaults: defaults,
            apiKeyLoader: {
                keychainReadCount += 1
                return "stored-secret"
            },
            apiKeySaver: { _ in }
        )

        for _ in 0..<5 {
            XCTAssertTrue(model.hasAPIKey)
            XCTAssertTrue(model.modelReady)
        }
        XCTAssertEqual(keychainReadCount, 0, "Rendering connection state must never query Keychain")
    }

    func testScaleNormalizationClampsAndSnapsToSupportedSteps() {
        XCTAssertEqual(InterfaceScalePolicy.normalized(0.79), 0.8, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.normalized(1.56), 1.5, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.normalized(1.24), 1.2, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.normalized(1.26), 1.3, accuracy: 0.0001)
    }

    func testScaleSteppingStopsAtAccessibleBoundaries() {
        XCTAssertEqual(InterfaceScalePolicy.increase(1.0), 1.1, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.increase(1.5), 1.5, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.decrease(1.0), 0.9, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.decrease(0.8), 0.8, accuracy: 0.0001)
    }

    func testScaleProvidesStablePercentageAndGeometryValues() {
        XCTAssertEqual(InterfaceScalePolicy.percentage(1.2), "120%")
        XCTAssertEqual(InterfaceScalePolicy.scaled(32, by: 1.5), 48, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.scaled(32, by: 0.8), 25.6, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.layoutScaled(240, by: 1.5), 300, accuracy: 0.0001)
        XCTAssertEqual(InterfaceScalePolicy.layoutScaled(240, by: 0.8), 216, accuracy: 0.0001)
    }

    func testPrimaryViewsDoNotBypassTheInterfaceScaleWithFixedSystemFonts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for file in ["Views.swift", "CreativeViews.swift", "AuraDesignSystem.swift"] {
            let source = try String(
                contentsOf: root.appendingPathComponent("Sources/ScriptForgeMac/\(file)"),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains(".font(.system(size:"),
                "\(file) contains a fixed system font that bypasses interface scaling"
            )
        }
    }
}
