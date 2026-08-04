# macOS native parity and release gates

The native app treats the Windows desktop product as a behavior baseline while using native SwiftUI, App Sandbox, Keychain, and Xcode distribution.

## Required parity

- Chinese/English interface.
- TXT import, chapter parsing, full-source preservation, and project-local copies.
- Lightweight Flash character naming, manual override, locked rename map, and old-name/generic-name checks.
- System-owned Flash/Pro routing.
- Story bible, global episode contracts, model-selected scene count, per-episode drafting, runtime simulation, semantic audit, targeted repair, overlapping-window series audit, and a blocking delivery gate.
- One-click six-module book analysis with evidence IDs, hierarchical digesting, up to eight revisions, and Markdown export.
- Clickable recent and archived project cards; 50 recent projects; automatic archive without automatic deletion; restore, duplicate, and explicit permanent deletion for archived projects.
- Editable versioned prompt assets with hoverable influence hints.
- Reset to initial home while retaining the previous project in the library.
- Structured output compatibility fallback for providers without JSON Schema response formats.

## Acceptance criteria

- A 60-second episode uses one to three story-selected scenes and is validated as a whole, normally 12–18 short dialogue lines and 129–195 spoken Chinese characters.
- No `角色8`-style placeholder or source-name leak reaches a delivered script.
- Adjacent episodes cannot repeat the same dominant conflict without new information or consequences.
- The first five seconds contain a visible conflict; the final five to eight seconds end on an action, discovery, or choice.
- Open blocker or major issues leave the result in `needs_review`; the UI never claims completion.
- The supplied private 1–10 chapter novel parses without truncation through `SCRIPT_FORGE_ACCEPTANCE_FILE`.

## Mac handoff

```bash
git clone --branch macos-native https://github.com/windAndLiberty/ScriptForge.git
cd ScriptForge/macos
./scripts/bootstrap-macos.sh
./scripts/ci-macos.sh
open ScriptForge.xcodeproj
```

Select the Apple Developer team in Signing & Capabilities. For Mac App Store distribution, use Xcode Organizer. For direct distribution, use Developer ID, hardened runtime, notarization, and `scripts/verify-release.sh`.
