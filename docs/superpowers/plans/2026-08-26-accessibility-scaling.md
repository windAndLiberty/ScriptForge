# Accessibility Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent 80%–150% semantic interface scaling and improve keyboard, VoiceOver, motion, transparency, and contrast accessibility.

**Architecture:** A tested `InterfaceScalePolicy` supplies a normalized SwiftUI environment value. Views render fonts and constrained shared geometry from that value, while App commands and Settings mutate one persisted value.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, XCTest, UserDefaults/AppStorage.

**Spec:** `docs/superpowers/specs/2026-08-26-accessibility-scaling-design.md`

## Global Constraints

- Preserve native vector/text rendering; do not apply `scaleEffect` to the application root.
- Persist a value from 0.8 through 1.5 in 0.1 steps, defaulting to 1.0.
- Keep Chinese and English interfaces complete.
- Preserve the macOS 14 minimum and the 1080×720 minimum window size.
- Keep existing Reduce Motion and Reduce Transparency behavior.

---

### Task 1: Scaling policy and environment

**Files:**
- Create: `macos/Sources/ScriptForgeMac/AccessibilitySettings.swift`
- Create: `macos/Tests/ScriptForgeMacTests/AccessibilitySettingsTests.swift`

**Interfaces:**
- Produces: `InterfaceScalePolicy.normalized(_:)`, `increase(_:)`, `decrease(_:)`, `percentage(_:)`, `EnvironmentValues.interfaceScale`, and `View.scaledFont(size:weight:design:)`.

- [ ] Write tests proving 0.79 clamps to 0.8, 1.56 clamps to 1.5, values snap to 0.1 steps, increase/decrease stop at boundaries, and 1.2 renders as `120%`.
- [ ] Run `swift test --filter AccessibilitySettingsTests` and verify the tests fail because the policy is missing.
- [ ] Implement the policy, environment key, and scaled font modifier.
- [ ] Run `swift test --filter AccessibilitySettingsTests` and verify all policy tests pass.

### Task 2: Persisted controls and keyboard commands

**Files:**
- Modify: `macos/Sources/ScriptForgeMac/ScriptForgeMacApp.swift`
- Modify: `macos/Sources/ScriptForgeMac/Views.swift`
- Modify: `macos/Sources/ScriptForgeMac/I18n.swift`
- Modify: `macos/Tests/ScriptForgeMacTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: `InterfaceScalePolicy` and `EnvironmentValues.interfaceScale` from Task 1.
- Produces: live Settings controls and View-menu commands for increase, decrease, and reset.

- [ ] Add failing localization assertions for Accessibility, Interface Scale, Zoom In, Zoom Out, Actual Size, and Reset Zoom.
- [ ] Run the localization test and verify it fails on untranslated strings.
- [ ] Add `@AppStorage`, root environment injection, localized commands with `Command +`, `Command -`, `Command 0`, and a scrollable Accessibility section in Settings.
- [ ] Add localized strings and accessible labels/values; run localization and policy tests until green.

### Task 3: Semantic rendering and responsive layout

**Files:**
- Modify: `macos/Sources/ScriptForgeMac/AuraDesignSystem.swift`
- Modify: `macos/Sources/ScriptForgeMac/Views.swift`
- Modify: `macos/Sources/ScriptForgeMac/CreativeViews.swift`
- Modify: `macos/Tests/ScriptForgeMacTests/AuraDesignSystemTests.swift`

**Interfaces:**
- Consumes: `EnvironmentValues.interfaceScale`.
- Produces: scaled fonts, shared control hit targets, sidebar/header/settings dimensions, motion-aware interactions, and increased-contrast borders.

- [ ] Add failing design-policy tests showing Reduce Motion disables interaction animation and increased contrast strengthens borders.
- [ ] Replace fixed `.font(.system(size:))` calls with `.scaledFont(size:)` in application views and shared styles.
- [ ] Scale shared buttons and constrained navigation dimensions; allow settings and narrow content to scroll/reflow at 150%.
- [ ] Add VoiceOver labels to icon-only theme/settings controls and retain visible symbols alongside status colors.
- [ ] Run `swift test --filter 'AuraDesignSystemTests|AccessibilitySettingsTests|LocalizationTests'` until green.

### Task 4: Completion gates

**Files:**
- Modify: `docs/macos-parity.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified Debug application and documented accessibility behavior.

- [ ] Run `git diff --check` and `swift test`; require zero failures.
- [ ] Run the Xcode Debug macOS build with `.build/development`; require `BUILD SUCCEEDED`.
- [ ] Launch the new Debug app and verify a new process is running.
- [ ] At 1080×720, inspect 80%, 100%, and 150%; verify Settings scrolls, headers do not clip, text remains sharp, and keyboard commands update the displayed percentage.
- [ ] Update `docs/macos-parity.md` with the implemented zoom range and accessibility behaviors.
