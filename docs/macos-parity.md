# macOS native parity and release gates

The native app treats the Windows desktop product as a behavior baseline while using native SwiftUI, App Sandbox, Keychain, and Xcode distribution.

## Required parity

- Chinese/English interface.
- Adaptive light/dark Aura interface with a persisted System/Light/Dark toolbar switcher, macOS 14 fallback rendering, semantic glass surfaces, pointing-hand affordances for clickable custom controls, and Reduce Motion/Reduce Transparency support.
- A separate Author Studio with six fixed workflows: book incubation, story bible, volume/chapter outlining, chapter production, continuity audit, and chapter polish.
- Recoverable workflow runs with local/model/validation/approval steps, offline model waiting, single-step retry, cancellation, input snapshots, and author approval barriers.
- Non-destructive chapter candidates, autosaved working drafts, accepted versions, paragraph comparison, restoration as a new version, and batches capped at ten chapters.
- Four-layer creative prompts: read-only system contract, versioned workflow template, project rules, and run instructions, with assembled-prompt/context preview and legacy prompt migration.
- All bundled adaptation, storyboard, analysis, and creative-workflow prompt defaults are English-only. Unmodified legacy defaults migrate to English, while user-authored overrides remain byte-for-byte intact in any language.
- Editable creative briefs, story-bible visibility controls, chapter cards, continuity issue logs, and relevant-context selection instead of whole-project prompt stuffing.
- Accepted-manuscript export as DOCX, Markdown, and structured JSON; immutable authoring-to-adaptation handoff snapshots.
- Window-wide single-file drag-and-drop plus picker-based local DOCX/TXT/Markdown import, with both entry points sharing the same creative/adaptation business flows, multi-encoding text decoding, prose/screenplay classification, full-source preservation, and project-local copies.
- Existing-screenplay pass-through that preserves episode numbers, scenes, visual/action blocks, dialogue, hooks, and original character names instead of re-adapting the source.
- Import diagnostics for missing, duplicated, empty, or out-of-order source units; ambiguous episodic prose remains on the prose workflow.
- Lightweight Flash character naming, manual override, locked rename map, and old-name/generic-name checks.
- System-owned Flash/Pro routing.
- Story bible, global episode contracts, model-selected scene count, per-episode drafting, runtime simulation, semantic audit, targeted repair, overlapping-window series audit, and a blocking delivery gate.
- One-click six-module book analysis with evidence IDs, hierarchical digesting, up to eight revisions, and Markdown export.
- Book-analysis progress, offline templates, online output contracts, revisions, section labels, and Markdown exports follow the UI language captured when the run starts; persisted reports retain that language without mixed-language relabeling.
- Clickable recent and archived project cards; 50 recent projects; automatic archive without automatic deletion; restore, duplicate, and explicit permanent deletion for archived projects.
- Editable versioned prompt assets with hoverable influence hints.
- Reset to initial home while retaining the previous project in the library.
- Structured output compatibility fallback for providers without JSON Schema response formats.
- Native storyboard production packages derived from the approved script, including shot timing, 9:16 composition, camera direction, sound, continuity, production notes, and keyframe prompts.
- Offline storyboard fallback plus optional BYOK image and speech generation through the user-configured Base URL, model names, and Keychain credential. No external workflow platform is required.
- Project-local media storage, preview/playback, Markdown storyboard export, and media-preserving project duplication.

## Acceptance criteria

- A 60-second episode uses one to three story-selected scenes and is validated as a whole, normally 12–18 short dialogue lines and 129–195 spoken Chinese characters.
- No `角色8`-style placeholder or source-name leak reaches a delivered script.
- Adjacent episodes cannot repeat the same dominant conflict without new information or consequences.
- The first five seconds contain a visible conflict; the final five to eight seconds end on an action, discovery, or choice.
- Open blocker or major issues leave the result in `needs_review`; the UI never claims completion.
- Private prose or screenplay fixtures parse without truncation through `SCRIPT_FORGE_ACCEPTANCE_FILE`; DOCX fixtures are accepted directly.
- Storyboard shot durations sum to the configured episode runtime, prompts include stable character anchors, and regenerating an approved script invalidates stale storyboard assets.
- A workflow interrupted during execution is recoverable after launch; generated or polished prose never replaces the accepted chapter before explicit approval.
- A three-chapter production run approves chapter cards once, creates three independent candidates, and pauses for chapter-level acceptance or a structural blocker.
- Schema-v4 projects open without a creative workspace and upgrade to schema v5 only when next saved; project duplication carries workflow runs, artifacts, chapter versions, and media.
- DOCX authoring export round-trips through the local importer without losing volume headings, chapter headings, or prose paragraphs.
- Dragging a supported file routes to Author Studio only when that workspace is active and otherwise routes to Adaptation Studio; multiple files, directories, and unsupported formats fail explicitly without persisting a partial project.

## Mac handoff

```bash
git clone --branch macos-native https://github.com/windAndLiberty/ScriptForge.git
cd ScriptForge/macos
./scripts/bootstrap-macos.sh
./scripts/ci-macos.sh
open ScriptForge.xcodeproj
```

Select the Apple Developer team in Signing & Capabilities. For Mac App Store distribution, use Xcode Organizer. For direct distribution, use Developer ID, hardened runtime, notarization, and `scripts/verify-release.sh`.
