# macOS native parity and release gates

The native app treats the Windows desktop product as a behavior baseline while using native SwiftUI, App Sandbox, Keychain, and Xcode distribution.

## Required parity

- Chinese/English interface.
- Adaptive light/dark Aura interface with a persisted System/Light/Dark toolbar switcher, macOS 14 fallback rendering, semantic glass surfaces, pointing-hand affordances for clickable custom controls, and Reduce Motion/Reduce Transparency support.
- A separate Author Studio with six fixed workflows: book incubation, story bible, volume/chapter outlining, chapter production, continuity audit, and chapter polish.
- Recoverable workflow runs with local/model/validation/approval steps, offline model waiting, single-step retry, cancellation, input snapshots, and author approval barriers.
- Non-destructive chapter candidates, autosaved working drafts, accepted versions, paragraph comparison, restoration as a new version, and batches capped at ten chapters.
- Four-layer creative prompts: read-only system contract, versioned workflow template, project rules, and run instructions, with assembled-prompt/context preview and legacy prompt migration.
- Authoring and analysis prompt assets remain versioned; the two single-chapter adaptation prompts are fixed program instructions and are never user-editable.
- Editable creative briefs, story-bible visibility controls, chapter cards, continuity issue logs, and relevant-context selection instead of whole-project prompt stuffing.
- Accepted-manuscript export as DOCX, Markdown, and structured JSON; immutable authoring-to-adaptation handoff snapshots.
- Window-wide single-file drag-and-drop plus picker-based local DOCX/TXT/Markdown import, with multi-encoding text decoding, full-source preservation, chapter selection when a document contains more than one chapter, and project-local copies.
- Single-chapter adaptation only: one selected source chapter produces one script through a linear workflow rather than episode planning or whole-book generation.
- Main-character renaming supports manual entry or one main-model generation call. Manual names win, and explicit user confirmation is required before adaptation can start.
- The adaptation workflow uses only the configured primary model. Pass one applies the fixed novel-promotion prompt; pass two applies the fixed video-promotion prompt to pass one's output, never to the original chapter.
- A user-entered Story Bible constraint block is included in both fixed passes and every later revision: world-setting name, world background (3,000 characters), core entries (200 characters), and forbidden terms (100 characters).
- The delivered script is directly editable. Every post-draft message is a script-revision instruction and sends the complete selected script, complete revision conversation, rename map, and Story Bible to the primary model.
- Each AI revision creates a new immutable candidate. The review UI switches between the previous and new candidate, and the user must explicitly select the baseline before another revision can begin.
- One-click six-module book analysis with evidence IDs, hierarchical digesting, up to eight revisions, and Markdown export.
- Book-analysis progress, offline templates, online output contracts, revisions, section labels, and Markdown exports follow the UI language captured when the run starts; persisted reports retain that language without mixed-language relabeling.
- Clickable recent and archived project cards; 50 recent projects; automatic archive without automatic deletion; restore, duplicate, and explicit permanent deletion for archived projects.
- Editable versioned prompt assets remain available to authoring and analysis workflows; they do not alter the fixed single-chapter adaptation prompts.
- Reset to initial home while retaining the previous project in the library.
- Structured output compatibility fallback for providers without JSON Schema response formats.

## Acceptance criteria

- Adaptation cannot start until every main character has a non-empty, unique, non-placeholder new name that differs from the source name and the user confirms the map.
- Both fixed generation calls use the same configured primary model; the second request contains the first response and does not contain the original chapter as its generation input.
- No `角色8`-style placeholder or source-name leak reaches a delivered script.
- The Story Bible limits are enforced locally before persistence and its current value is included in every generation and revision request.
- After every AI revision, the revision composer remains blocked until the user chooses either the previous or new version as the next baseline.
- Private prose or screenplay fixtures parse without truncation through `SCRIPT_FORGE_ACCEPTANCE_FILE`; DOCX fixtures are accepted directly.
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
