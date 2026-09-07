import XCTest
@testable import ScriptForgeMac

final class AuraDesignSystemTests: XCTestCase {
    func testAppearanceMapsToExpectedColorScheme() {
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
    }

    func testReduceMotionAndInactiveApplicationPauseAuraAnimation() {
        XCTAssertTrue(AuraRenderingPolicy(
            reduceMotion: true,
            reduceTransparency: false,
            applicationIsActive: true
        ).pausesAnimation)
        XCTAssertTrue(AuraRenderingPolicy(
            reduceMotion: false,
            reduceTransparency: false,
            applicationIsActive: false
        ).pausesAnimation)
        XCTAssertFalse(AuraRenderingPolicy(
            reduceMotion: false,
            reduceTransparency: false,
            applicationIsActive: true
        ).pausesAnimation)
    }

    func testReduceTransparencySelectsOpaqueRenderingPath() {
        XCTAssertFalse(AuraRenderingPolicy(
            reduceMotion: false,
            reduceTransparency: true,
            applicationIsActive: true
        ).usesTranslucentSurfaces)
        XCTAssertTrue(AuraRenderingPolicy(
            reduceMotion: false,
            reduceTransparency: false,
            applicationIsActive: true
        ).usesTranslucentSurfaces)
    }

    func testAccessibilityPolicyDisablesInteractionMotionAndStrengthensBorders() {
        let reducedMotion = AuraRenderingPolicy(
            reduceMotion: true,
            reduceTransparency: false,
            applicationIsActive: true,
            increasedContrast: false
        )
        XCTAssertNil(reducedMotion.interactionAnimationDuration)

        let increasedContrast = AuraRenderingPolicy(
            reduceMotion: false,
            reduceTransparency: false,
            applicationIsActive: true,
            increasedContrast: true
        )
        XCTAssertEqual(increasedContrast.borderWidth, 2)
        XCTAssertEqual(increasedContrast.interactionAnimationDuration, 0.16)
    }
}
