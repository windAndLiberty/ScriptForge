# ScriptForge Accessibility Scaling Design

## Scope

ScriptForge will provide a persistent application-wide interface scale from 80% through 150%, with 10% steps and a 100% default. Scaling changes text, shared controls, the sidebar, header, settings panel, and other constrained navigation surfaces without raster-scaling the window. Content areas remain responsive and scroll when their readable minimum size no longer fits.

## Interaction

- Settings contains an Accessibility section with decrease, increase, reset, and a slider showing the current percentage.
- View-menu commands expose Zoom In (`Command +`), Zoom Out (`Command -`), and Actual Size (`Command 0`).
- Values persist in `UserDefaults` and update every open ScriptForge view immediately.
- Zoom controls clamp at 80% and 150%; disabled controls communicate their state to VoiceOver.

## Architecture

`InterfaceScalePolicy` owns normalization, stepping, labels, and storage keys. A SwiftUI environment value distributes the normalized scale. `scaledFont` replaces fixed point-size fonts, while shared controls and constrained top-level layouts read the same environment value for hit targets and dimensions. This preserves sharp native rendering and correct pointer/accessibility geometry.

## Accessibility

- Icon-only header and zoom controls receive localized VoiceOver labels and values.
- Native keyboard focus and controls are retained; settings fields keep explicit accessible labels.
- Existing Reduce Motion and Reduce Transparency support remains authoritative. Shared hover/press animations stop when Reduce Motion is enabled.
- Increased system contrast strengthens shared borders; status must not rely on color alone where this work touches it.
- English and Simplified Chinese copy are provided for every new visible string.

## Verification

Unit tests cover normalization, stepping, percentage display, and persisted range boundaries. Design-system tests cover animation/contrast policies. Localization tests cover all new strings. SwiftPM tests, Xcode Debug build, and a smoke launch are required; manual checks cover 80%, 100%, and 150% at the 1080×720 minimum window size.
