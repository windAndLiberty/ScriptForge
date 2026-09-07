import { compileCreativePrompt, defaultPromptOverride } from "./prompts";
import {
  artifactKind,
  buildCreativeContext,
  CREATIVE_PAYLOAD_SCHEMA,
  startWorkflow,
  validatePayload,
  workflowDefinition,
} from "./workflows";
import type {
  ChapterCard,
  ChapterDocument,
  ChapterVersionSource,
  ContinuityIssue,
  CreativeGenerationPayload,
  CreativeStoryBible,
  CreativeWorkspace,
  CreativeWorkflowId,
  StoryBibleCardKind,
  VolumeOutline,
  WorkflowArtifactReference,
  WorkflowRun,
  WorkflowRunInput,
} from "./types";

const now = () => new Date().toISOString();
const wordCount = (value: string) =>
  value.trim().split(/\s+/).filter(Boolean).length ||
  [...value].filter((character) => !/\s/.test(character)).length;

function clone<T>(value: T): T {
  return structuredClone(value);
}

function bibleKind(value: string): StoryBibleCardKind {
  const lower = value.toLowerCase();
  if (lower.includes("character")) return "character";
  if (lower.includes("location")) return "location";
  if (lower.includes("faction")) return "faction";
  if (lower.includes("item") || lower.includes("object")) return "item";
  if (lower.includes("ability") || lower.includes("power")) return "ability";
  if (lower.includes("style")) return "style";
  return "worldRule";
}

function makeCards(payload: CreativeGenerationPayload, run: WorkflowRun, workspace: CreativeWorkspace) {
  const next = Math.max(0, ...workspace.chapters.map((chapter) => chapter.number)) + 1;
  const count = Math.max(1, run.input.batchCount);
  return payload.items.slice(0, count).map((item, index): ChapterCard => {
    const selected = workspace.chapters.find((chapter) => chapter.id === run.input.selectedChapterIds[index]);
    const details = [...item.details, "", "", "", "", ""];
    return {
      id: crypto.randomUUID(),
      number: selected?.number ?? next + index,
      volumeNumber: selected?.volumeNumber ?? workspace.outlines.at(-1)?.number ?? 1,
      title: item.name,
      objective: details[0] || item.summary,
      conflict: details[1],
      reveal: details[2],
      hook: details[3],
      sceneBeats: details.slice(4).filter(Boolean),
      activeForeshadowingIds: [],
    };
  });
}

function mergePlannedChapters(cards: ChapterCard[], workspace: CreativeWorkspace) {
  for (const card of cards) {
    const existing = workspace.chapters.find((chapter) => chapter.number === card.number);
    if (existing) {
      existing.title = card.title;
      existing.cardId = card.id;
    } else {
      workspace.chapters.push({
        id: crypto.randomUUID(),
        number: card.number,
        volumeNumber: card.volumeNumber,
        title: card.title,
        cardId: card.id,
        status: "planned",
        versions: [],
      });
    }
  }
  workspace.chapters.sort((a, b) => a.number - b.number);
  workspace.selectedChapterId ||= workspace.chapters[0]?.id;
}

async function writePayload(projectId: string, run: WorkflowRun, payload: CreativeGenerationPayload) {
  if (!window.desktopAPI) throw new Error("Creative workflows require the desktop application.");
  const step = run.steps[run.activeStepIndex];
  const id = crypto.randomUUID();
  const contentPath = await window.desktopAPI.writeProjectJson({
    projectId,
    category: "artifacts",
    itemId: id,
    value: payload,
  });
  const reference: WorkflowArtifactReference = {
    id,
    runId: run.id,
    workflowId: run.workflowId,
    kind: artifactKind(run.workflowId, step.id),
    title: payload.title,
    summary: payload.summary,
    contentPath,
    isCandidate: true,
    createdAt: now(),
  };
  run.artifactIds.push(id);
  step.artifactIds.push(id);
  return reference;
}

async function createChapterCandidates(
  projectId: string,
  payload: CreativeGenerationPayload,
  run: WorkflowRun,
  workspace: CreativeWorkspace,
  source: ChapterVersionSource,
) {
  const selected = run.input.selectedChapterIds.length
    ? run.input.selectedChapterIds.slice(0, 10)
    : workspace.chapters
        .filter((chapter) => chapter.status === "planned" || chapter.status === "accepted")
        .sort((a, b) => a.number - b.number)
        .slice(0, run.input.batchCount)
        .map((chapter) => chapter.id);
  if (!selected.length) throw new Error("Select or plan at least one chapter first.");
  const items = payload.items.length
    ? payload.items
    : [{ kind: "chapter", name: payload.title, summary: payload.summary, content: payload.markdown, details: [] }];
  for (const [index, chapterId] of selected.entries()) {
    const chapter = workspace.chapters.find((item) => item.id === chapterId);
    if (!chapter) continue;
    const item = items[Math.min(index, items.length - 1)];
    const content = item.content.trim() || payload.markdown;
    const id = crypto.randomUUID();
    const contentPath = await window.desktopAPI!.writeProjectText({
      projectId,
      category: `chapters/${chapter.id}/versions`,
      itemId: id,
      content,
    });
    chapter.versions.push({
      id,
      createdAt: now(),
      source,
      contentPath,
      summary: item.summary,
      wordCount: wordCount(content),
      promptSnapshotId: run.promptSnapshotId,
      accepted: false,
    });
    chapter.candidateVersionId = id;
    chapter.status = "review";
  }
}

async function persistRun(projectId: string, run: WorkflowRun, workspace: CreativeWorkspace) {
  const path = await window.desktopAPI!.writeProjectJson({
    projectId,
    category: "runs",
    itemId: run.id,
    value: run,
  });
  const reference = workspace.runs.find((item) => item.id === run.id);
  const summary = { id: run.id, workflowId: run.workflowId, status: run.status, path, updatedAt: run.updatedAt };
  if (reference) Object.assign(reference, summary);
  else workspace.runs.push(summary);
}

export async function createRun(projectId: string, workspace: CreativeWorkspace, id: CreativeWorkflowId, input: WorkflowRunInput) {
  const next = clone(workspace);
  const run = startWorkflow(id, input);
  await persistRun(projectId, run, next);
  return { workspace: next, run };
}

export async function advanceRun(args: {
  projectId: string;
  workspace: CreativeWorkspace;
  run: WorkflowRun;
  outputLanguage: string;
  hasModel: boolean;
  modelId?: string;
}): Promise<{ workspace: CreativeWorkspace; run: WorkflowRun }> {
  const workspace = clone(args.workspace);
  const run = clone(args.run);
  const definition = workflowDefinition(run.workflowId);
  run.status = "running";
  run.modelId = args.modelId;

  while (run.activeStepIndex < run.steps.length) {
    const step = run.steps[run.activeStepIndex];
    const stepDefinition = definition.steps.find((item) => item.id === step.id)!;
    if (step.status === "skipped" || step.status === "completed") {
      run.activeStepIndex += 1;
      continue;
    }
    if (step.kind === "approval") {
      step.status = "waiting";
      run.status = "waitingForApproval";
      run.updatedAt = now();
      await persistRun(args.projectId, run, workspace);
      return { workspace, run };
    }
    if (step.kind === "local") {
      step.status = "completed";
      step.startedAt ||= now();
      step.completedAt = now();
      run.activeStepIndex += 1;
      continue;
    }
    if (step.kind === "validation") {
      const hasBlocker = workspace.continuityIssues.some((issue) => issue.severity === "blocker");
      if (hasBlocker && run.workflowId === "chapterProduction") {
        step.status = "failed";
        step.error = "A blocking continuity issue requires author review.";
        run.status = "interrupted";
        run.error = step.error;
        run.updatedAt = now();
        await persistRun(args.projectId, run, workspace);
        return { workspace, run };
      }
      step.status = "completed";
      step.completedAt = now();
      run.activeStepIndex += 1;
      continue;
    }
    if (!args.hasModel || !window.desktopAPI) {
      step.status = "waiting";
      run.status = "waitingForModel";
      run.updatedAt = now();
      await persistRun(args.projectId, run, workspace);
      return { workspace, run };
    }
    step.status = "running";
    step.startedAt ||= now();
    try {
      const override = workspace.promptOverrides.find((item) => item.workflowId === run.workflowId)
        || defaultPromptOverride(run.workflowId);
      const compiled = compileCreativePrompt({
        workflowId: run.workflowId,
        workflowOverride: override,
        projectInstruction: workspace.projectInstruction,
        runInstruction: run.input.instruction,
        variables: {
          ...run.input.parameters,
          seed: run.input.seed,
          batchCount: String(run.input.batchCount),
          outputLanguage: args.outputLanguage,
        },
        context: buildCreativeContext(workspace),
        excludedContextIds: run.input.excludedContextIds,
      });
      if (!run.promptSnapshotId) {
        run.promptSnapshotId = compiled.snapshot.id;
        const snapshotPath = await window.desktopAPI.writeProjectJson({
          projectId: args.projectId,
          category: "artifacts",
          itemId: compiled.snapshot.id,
          value: compiled.snapshot,
        });
        workspace.artifacts.push({
          id: compiled.snapshot.id,
          runId: run.id,
          workflowId: run.workflowId,
          kind: "promptSnapshot",
          title: "Prompt snapshot",
          summary: compiled.snapshot.contextLabels.join(", "),
          contentPath: snapshotPath,
          isCandidate: false,
          createdAt: compiled.snapshot.createdAt,
        });
      }
      const payload = await window.desktopAPI.callStructured<CreativeGenerationPayload>({
        instructions: compiled.instructions,
        input: `${compiled.input}\n\n[Batch Count]\n${run.input.batchCount}`,
        name: `creative_${run.workflowId}_${step.id}`,
        schema: CREATIVE_PAYLOAD_SCHEMA as unknown as Record<string, unknown>,
        route: stepDefinition.route,
      });
      validatePayload(payload, run);
      const artifact = await writePayload(args.projectId, run, payload);
      workspace.artifacts.push(artifact);
      if (run.workflowId === "chapterProduction" && step.id === "draft") {
        await createChapterCandidates(args.projectId, payload, run, workspace, "generated");
      }
      if (run.workflowId === "chapterPolish" && step.id === "polish") {
        await createChapterCandidates(args.projectId, payload, run, workspace, "polished");
      }
      step.status = "completed";
      step.completedAt = now();
      run.activeStepIndex += 1;
    } catch (error) {
      step.status = "failed";
      step.error = error instanceof Error ? error.message : "Model request failed.";
      run.status = "failed";
      run.error = step.error;
      run.updatedAt = now();
      await persistRun(args.projectId, run, workspace);
      return { workspace, run };
    }
  }
  run.status = "completed";
  run.updatedAt = now();
  await persistRun(args.projectId, run, workspace);
  return { workspace, run };
}

async function latestPayload(projectId: string, workspace: CreativeWorkspace, run: WorkflowRun, kind?: string) {
  const artifact = [...workspace.artifacts].reverse().find((item) =>
    item.runId === run.id && item.kind !== "promptSnapshot" && (!kind || item.kind === kind));
  if (!artifact) throw new Error("No candidate artifact is available.");
  const payload = await window.desktopAPI!.readProjectJson<CreativeGenerationPayload>({ projectId, relativePath: artifact.contentPath });
  return { artifact, payload };
}

export async function approveRun(projectId: string, sourceWorkspace: CreativeWorkspace, sourceRun: WorkflowRun) {
  const workspace = clone(sourceWorkspace);
  const run = clone(sourceRun);
  const step = run.steps[run.activeStepIndex];
  if (!step || step.kind !== "approval") throw new Error("This run is not waiting for approval.");
  if (
    (run.workflowId === "chapterProduction" && step.id === "approve-drafts") ||
    run.workflowId === "chapterPolish"
  ) {
    const unresolved = workspace.chapters.filter((chapter) => chapter.candidateVersionId);
    if (unresolved.length) {
      throw new Error(`Review each candidate chapter before continuing (${unresolved.length} remaining).`);
    }
  }
  if (!(run.workflowId === "chapterProduction" && step.id === "approve-drafts") && run.workflowId !== "chapterPolish") {
    const { artifact, payload } = await latestPayload(projectId, workspace, run,
      run.workflowId === "chapterProduction" ? "chapterCards" : undefined);
    if (run.workflowId === "incubation") {
      workspace.briefs.push({
        id: crypto.randomUUID(), title: payload.title,
        genre: run.input.parameters.genre || payload.items[0]?.kind || "Unspecified",
        targetAudience: run.input.parameters.audience || "General readers",
        premise: payload.summary, sellingPoints: payload.items.map((item) => item.summary).filter(Boolean),
        protagonist: payload.items.find((item) => item.kind.toLowerCase().includes("character"))?.name || run.input.parameters.protagonist || "To be confirmed",
        centralConflict: run.input.parameters.conflict || payload.items[0]?.content || payload.summary,
        tone: run.input.parameters.tone || "To be confirmed", constraints: payload.items.flatMap((item) => item.details), createdAt: now(),
      });
      workspace.activeBriefId = workspace.briefs.at(-1)?.id;
    } else if (run.workflowId === "storyBible") {
      const bible: CreativeStoryBible = {
        id: crypto.randomUUID(), title: payload.title, styleGuide: payload.markdown, forbiddenElements: [], createdAt: now(),
        cards: payload.items.map((item) => ({ id: crypto.randomUUID(), kind: bibleKind(item.kind), name: item.name, summary: item.summary,
          details: Object.fromEntries(item.details.map((value, index) => [`Detail ${index + 1}`, value])), aliases: [], visibility: "included", sourceChapterNumbers: [] })),
      };
      workspace.storyBibles.push(bible); workspace.activeStoryBibleId = bible.id;
    } else if (run.workflowId === "outline") {
      const cards = makeCards(payload, run, workspace);
      const outline: VolumeOutline = { id: crypto.randomUUID(), number: workspace.outlines.length + 1, title: payload.title, arcSummary: payload.summary, chapterCards: cards, createdAt: now() };
      workspace.outlines.push(outline); mergePlannedChapters(cards, workspace);
    } else if (run.workflowId === "chapterProduction") {
      const cards = makeCards(payload, run, workspace);
      const outline = workspace.outlines.at(-1) || { id: crypto.randomUUID(), number: 1, title: "Volume 1", arcSummary: payload.summary, chapterCards: [], createdAt: now() };
      cards.forEach((card) => {
        const index = outline.chapterCards.findIndex((item) => item.number === card.number);
        if (index >= 0) outline.chapterCards[index] = card; else outline.chapterCards.push(card);
      });
      outline.chapterCards.sort((a, b) => a.number - b.number);
      if (!workspace.outlines.length) workspace.outlines.push(outline);
      mergePlannedChapters(cards, workspace);
    } else if (run.workflowId === "continuityAudit") {
      workspace.continuityIssues = payload.items.map((item): ContinuityIssue => ({
        id: crypto.randomUUID(),
        severity: /block|critical|severe/i.test(item.kind) ? "blocker" : /warn/i.test(item.kind) ? "warning" : "info",
        category: item.name, chapterNumbers: [], evidence: item.content, suggestion: item.details.join("\n"),
      }));
    }
    artifact.isCandidate = false;
  }
  step.status = "completed";
  step.completedAt = now();
  run.activeStepIndex += 1;
  run.status = "running";
  run.updatedAt = now();
  await persistRun(projectId, run, workspace);
  return { workspace, run };
}

export async function setChapterCandidate(projectId: string, source: CreativeWorkspace, chapterId: string, accept: boolean) {
  const workspace = clone(source);
  const chapter = workspace.chapters.find((item) => item.id === chapterId);
  if (!chapter?.candidateVersionId) throw new Error("No candidate chapter is available.");
  if (accept) {
    chapter.versions.forEach((version) => { version.accepted = version.id === chapter.candidateVersionId; });
    chapter.currentVersionId = chapter.candidateVersionId;
    chapter.status = "accepted";
  } else {
    chapter.status = chapter.currentVersionId ? "accepted" : "planned";
  }
  chapter.candidateVersionId = undefined;
  return workspace;
}

export async function saveManualChapter(projectId: string, source: CreativeWorkspace, chapterId: string, content: string) {
  const workspace = clone(source);
  const chapter = workspace.chapters.find((item) => item.id === chapterId);
  if (!chapter) throw new Error("Select a chapter first.");
  const id = crypto.randomUUID();
  const contentPath = await window.desktopAPI!.writeProjectText({ projectId, category: `chapters/${chapterId}/versions`, itemId: id, content });
  chapter.versions.forEach((version) => { version.accepted = false; });
  chapter.versions.push({ id, createdAt: now(), source: "manual", contentPath, summary: content.slice(0, 120), wordCount: wordCount(content), accepted: true });
  chapter.currentVersionId = id; chapter.candidateVersionId = undefined; chapter.status = "accepted";
  return workspace;
}

export async function restoreChapterVersion(projectId: string, source: CreativeWorkspace, chapterId: string, versionId: string) {
  const chapter = source.chapters.find((item) => item.id === chapterId);
  const version = chapter?.versions.find((item) => item.id === versionId);
  if (!chapter || !version) throw new Error("The selected version no longer exists.");
  const content = await window.desktopAPI!.readProjectText({ projectId, relativePath: version.contentPath });
  const workspace = await saveManualChapter(projectId, source, chapterId, content);
  const restored = workspace.chapters.find((item) => item.id === chapterId)!.versions.at(-1)!;
  restored.source = "restored"; restored.promptSnapshotId = version.promptSnapshotId;
  return workspace;
}

export function cancelRun(source: WorkflowRun) {
  const run = clone(source); run.status = "cancelled"; run.updatedAt = now(); return run;
}

export function retryRun(source: WorkflowRun) {
  const run = clone(source); const step = run.steps[run.activeStepIndex];
  if (step) { step.status = "pending"; step.error = undefined; }
  run.status = "queued"; run.error = undefined; run.updatedAt = now(); return run;
}

export function regenerateRun(source: WorkflowRun) {
  const run = clone(source);
  let index = Math.max(0, run.activeStepIndex - 1);
  while (index > 0 && run.steps[index].kind !== "model") index -= 1;
  if (run.steps[index]?.kind !== "model") throw new Error("No model step is available to regenerate.");
  run.steps[index].status = "pending";
  run.steps[index].error = undefined;
  const approval = run.steps[run.activeStepIndex];
  if (approval?.kind === "approval") approval.status = "pending";
  run.activeStepIndex = index;
  run.status = "queued";
  run.error = undefined;
  run.updatedAt = now();
  return run;
}

export async function readChapterText(projectId: string, chapter?: ChapterDocument, candidate = false) {
  const id = candidate ? chapter?.candidateVersionId : chapter?.currentVersionId;
  const version = chapter?.versions.find((item) => item.id === id);
  return version ? window.desktopAPI!.readProjectText({ projectId, relativePath: version.contentPath }) : "";
}

export async function updateCandidateArtifact(
  projectId: string,
  workspace: CreativeWorkspace,
  run: WorkflowRun,
  payload: CreativeGenerationPayload,
) {
  const artifact = [...workspace.artifacts].reverse().find((item) => item.runId === run.id && item.isCandidate && item.kind !== "promptSnapshot");
  if (!artifact) throw new Error("No candidate artifact is available.");
  await window.desktopAPI!.writeProjectJson({ projectId, category: "artifacts", itemId: artifact.id, value: payload });
}
