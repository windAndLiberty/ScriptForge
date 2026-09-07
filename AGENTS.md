# ScriptForge agent guide

## Repository map

- `src/`, `electron/`: shipped Windows/Electron behavior baseline. Do not change during macOS-only work unless the task explicitly asks for cross-platform changes.
- `macos/Sources/ScriptForgeMac`: native SwiftUI app and pipeline.
- `macos/Tests/ScriptForgeMacTests`: Swift unit and integration tests.
- `macos/project.yml`: XcodeGen source of truth. Do not hand-edit generated `ScriptForge.xcodeproj`.
- `docs/macos-parity.md`: required product parity and release gates.

## Product invariants

- The user configures two models but never edits the internal route. Flash handles naming, extraction, and independent audits; Pro handles story architecture, drafting, and targeted repair.
- Never add a user-facing scenes-per-episode option. The model chooses within the duration budget and deterministic QA validates the whole episode.
- Never emit placeholders such as `角色8`, `人物1`, or `男主1`. Manual names always override model names.
- Recent projects are capped at 50. Overflow is archived, never deleted. Permanent deletion is available only for archived projects and requires confirmation.
- API keys live only in macOS Keychain. Imported novels, generated scripts, credentials, signing assets, and acceptance corpora must not be committed.
- Structured output constraints describe shape. Creative completeness is checked after generation; do not enforce nine dialogue items per scene.

## Verification

On macOS:

```bash
cd macos
./scripts/bootstrap-macos.sh
swift test
./scripts/ci-macos.sh
```

For the private acceptance novel:

```bash
SCRIPT_FORGE_ACCEPTANCE_FILE=/absolute/path/to/novel.txt ./scripts/ci-macos.sh
```

Windows can edit and statically inspect Swift source, but must never claim Xcode build, signing, sandbox, or notarization success. GitHub macOS CI and a real Mac are authoritative.

## Definition of done

- Relevant Swift tests exist and pass.
- `xcodebuild` passes without signing in CI.
- The UI remains Chinese/English, keyboard-accessible, and resizable at 1080×720 or larger.
- No secret, private novel, generated draft, certificate, provisioning profile, archive, or DerivedData appears in Git.
- Product parity and release documentation is updated when behavior changes.
