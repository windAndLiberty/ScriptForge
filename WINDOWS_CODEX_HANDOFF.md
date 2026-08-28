# ScriptForge Windows parity handoff

Copy the prompt below into Codex on the Windows computer after cloning this repository.

## Prompt for Windows Codex

You are finishing the native Windows acceptance and packaging pass for ScriptForge. Work in the existing repository and do not replace the architecture or remove features.

### Source and branch

1. Clone `https://github.com/windAndLiberty/ScriptForge.git`.
2. Check out `windows-parity`.
3. Read `AGENTS.md` completely before making changes.
4. Read this file completely.

### Product contract

The Windows build must retain the same product capabilities as the macOS 1.0 build:

- local-first operation and OpenAI-compatible BYOK only;
- secure OS-backed API-key storage; never write a key to a project, log, screenshot, fixture, or source file;
- bilingual Simplified Chinese/English UI without mixed-language surfaces;
- dark and light Fluid Aura themes plus 85%–130% UI scaling and keyboard focus accessibility;
- drag-and-drop and picker import for TXT, Markdown, RTF, DOCX, legacy DOC, PDF, HTML, and ODT;
- one-click book analysis, adaptation pipeline, character renaming, story bible, episode planning, screenplay editing, quality gate, storyboard production, and optional BYOK image/speech generation;
- Author Studio with all six fixed workflows: New Book Incubation, Story Bible, Volume & Chapter Planning, Chapter Production, Continuity Audit, and Chapter Polish;
- workflow recovery, waiting-for-model state, single paid-request retry behavior, batch-card approval once, sequential candidate review, and stop on blocker;
- generated text is always a candidate and never silently overwrites accepted author text;
- chapter manual save, candidate accept/reject, edit-and-accept, version history, and restore;
- four prompt layers, prompt revision history, default English prompt assets, final prompt/context preview, and context exclusion;
- Markdown, DOCX, and JSON Author Studio exports, plus immutable handoff to Adaptation Studio;
- schema v5 project folders with atomic `project.json`, `creative/workspace.json`, `runs/`, `artifacts/`, `chapters/<id>/versions/`, `handoffs/`, and `media/` files.

Do not add a third-party workflow platform, hosted document service, bundled API key, or automatic paid retries. Do not rename generic characters to placeholders such as “Male Lead” or “Female Lead.” Do not reintroduce user-facing scene-count controls.

### Required Windows verification

Use PowerShell from the repository root:

```powershell
npm ci
npm test
npm run build
npm run smoke:desktop
npm run dist:windows
```

Then install the generated `release\ScriptForge-1.0.0-x64.exe` into a non-administrator user account and perform these checks with evidence:

1. Launch, switch Chinese/English, switch dark/light, and test 85%, 100%, and 130% scale at Windows display scaling 100% and 150%.
2. Verify every sidebar and top-right control shows a hand cursor and a visible keyboard focus ring.
3. Drag and picker-import real TXT, MD, RTF, DOCX, DOC, PDF, HTML, and ODT samples. Confirm chapter order and non-empty body text. Record unsupported/encrypted/scanned-PDF messages clearly rather than crashing.
4. Import the repository test fixture and, if available on this machine, `48-script.docx`. Confirm one-click book analysis, adaptation, screenplay, quality, storyboard, and export surfaces.
5. Without an API key, confirm local editing, deterministic checks, offline storyboard generation, project persistence, and all exports still work. Model steps must show `Waiting for model settings`.
6. Configure a disposable BYOK endpoint. Verify Responses and Chat Completions modes, primary/flash routing, endpoint normalization, HTTP 405 guidance, truncated JSON handling, and exactly one user-triggered retry.
7. Run a three-chapter production workflow. Confirm one batch-card approval, three separate candidate decisions, no silent overwrite, blocker interruption, restart recovery from the first unfinished step, and version restoration.
8. Export accepted chapters as DOCX, Markdown, and JSON. Re-import the DOCX and compare volume/chapter order and body presence. Confirm JSON contains no API key.
9. Generate one offline storyboard package. If image and speech models are available, generate one keyframe and one voice file and confirm both paths are inside the project directory.
10. Close the app during a workflow, relaunch, resume, duplicate/archive a project, and confirm the entire project folder remains self-contained.
11. Uninstall and reinstall. Confirm uninstall behavior is clear and that project data is not silently deleted.

Inspect `acceptance\ui-empty.png`, `ui-workbench.png`, `ui-workbench-en.png`, `ui-author-studio-en.png`, `ui-projects-en.png`, and `ui-prompts-en.png`. Fix clipping, overlap, illegible dark-theme controls, mixed Chinese text in English mode, or scale-related overflow.

### Packaging and Store build

- The NSIS package is the local acceptance artifact.
- `npm run dist:windows:store` builds the AppX/MSIX-family artifact, but before Store submission replace any placeholder identity/publisher metadata with the exact values from the existing Microsoft Partner Center app identity. Never guess the Publisher ID.
- Do not claim Microsoft Store readiness until Windows App Certification Kit and an installed packaged-app smoke test both pass.

### Completion output

Fix issues found on Windows, add or update automated tests for every code defect, rerun all five commands, and commit the changes on `windows-parity`. Push the branch and report:

- commit hash;
- test count and result;
- NSIS artifact name and SHA-256;
- AppX/MSIX artifact name and SHA-256 if Partner Center identity was supplied;
- Windows version, architecture, display scale, and install mode used;
- the acceptance checklist with pass/fail evidence;
- any remaining blocker that requires an account, credential, or Microsoft Partner Center value.

