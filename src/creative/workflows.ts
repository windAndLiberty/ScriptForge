import type {
  CreativeArtifactKind,
  CreativeGenerationPayload,
  CreativeWorkspace,
  CreativeWorkflowId,
  WorkflowDefinition,
  WorkflowRun,
  WorkflowRunInput,
} from "./types";

const commonFields = [
  { id: "seed", label: "Starting material", required: false },
  { id: "instruction", label: "Run instructions", required: false },
];

export const WORKFLOW_DEFINITIONS: WorkflowDefinition[] = [
  {
    id: "incubation",
    title: "New Book Incubation",
    summary: "Shape an idea into a market-aware, actionable creative brief.",
    inputFields: [...commonFields],
    artifactKinds: ["brief"],
    steps: [
      { id: "prepare", title: "Prepare material", kind: "local" },
      { id: "generate", title: "Generate proposal", kind: "model", route: "primary" },
      { id: "approve", title: "Author approval", kind: "approval" },
    ],
  },
  {
    id: "storyBible",
    title: "Story Bible",
    summary: "Maintain characters, rules, places, factions, objects, abilities, and style.",
    inputFields: [...commonFields],
    artifactKinds: ["storyBible"],
    steps: [
      { id: "collect", title: "Collect facts", kind: "local" },
      { id: "generate", title: "Build story bible", kind: "model", route: "primary" },
      { id: "validate", title: "Validate facts", kind: "validation", optional: true },
      { id: "approve", title: "Author approval", kind: "approval" },
    ],
  },
  {
    id: "outline",
    title: "Volume & Chapter Planning",
    summary: "Create volume arcs, chapter cards, foreshadowing, and payoff points.",
    inputFields: [...commonFields, { id: "chapterCount", label: "Chapter count", required: true, defaultValue: "10" }],
    artifactKinds: ["outline", "chapterCards"],
    steps: [
      { id: "prepare", title: "Prepare constraints", kind: "local" },
      { id: "generate", title: "Generate chapter cards", kind: "model", route: "primary" },
      { id: "validate", title: "Validate coverage", kind: "validation", optional: true },
      { id: "approve", title: "Author approval", kind: "approval" },
    ],
  },
  {
    id: "chapterProduction",
    title: "Chapter Production",
    summary: "Approve a batch of chapter cards once, then draft chapters sequentially.",
    inputFields: [...commonFields, { id: "targetWords", label: "Words per chapter", required: true, defaultValue: "2000" }],
    artifactKinds: ["chapterCards", "chapterDraft"],
    steps: [
      { id: "context", title: "Select context", kind: "local" },
      { id: "chapter-cards", title: "Generate batch cards", kind: "model", route: "primary" },
      { id: "approve-cards", title: "Approve batch cards", kind: "approval" },
      { id: "draft", title: "Draft chapters", kind: "model", route: "primary" },
      { id: "validate", title: "Continuity check", kind: "validation", optional: true },
      { id: "approve-drafts", title: "Approve chapter draft", kind: "approval" },
    ],
  },
  {
    id: "continuityAudit",
    title: "Continuity Audit",
    summary: "Audit states, knowledge, timeline, objects, abilities, and foreshadowing.",
    inputFields: [...commonFields],
    artifactKinds: ["auditReport"],
    steps: [
      { id: "collect", title: "Collect evidence", kind: "local" },
      { id: "audit", title: "Audit continuity", kind: "model", route: "flash" },
      { id: "validate", title: "Validate evidence", kind: "validation", optional: true },
      { id: "approve", title: "Review findings", kind: "approval" },
    ],
  },
  {
    id: "chapterPolish",
    title: "Chapter Polish",
    summary: "Improve pacing, dialogue, repetition, POV, and custom concerns.",
    inputFields: [...commonFields],
    artifactKinds: ["polishedChapter"],
    steps: [
      { id: "prepare", title: "Prepare chapter", kind: "local" },
      { id: "polish", title: "Polish candidate", kind: "model", route: "primary" },
      { id: "validate", title: "Verify facts", kind: "validation", optional: true },
      { id: "approve", title: "Author approval", kind: "approval" },
    ],
  },
];

export const CREATIVE_PAYLOAD_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["title", "summary", "markdown", "items"],
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    markdown: { type: "string" },
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["kind", "name", "summary", "content", "details"],
        properties: {
          kind: { type: "string" },
          name: { type: "string" },
          summary: { type: "string" },
          content: { type: "string" },
          details: { type: "array", items: { type: "string" } },
        },
      },
    },
  },
} as const;

export function workflowDefinition(id: CreativeWorkflowId) {
  const value = WORKFLOW_DEFINITIONS.find((item) => item.id === id);
  if (!value) throw new Error(`Unknown workflow: ${id}`);
  return value;
}

export function startWorkflow(id: CreativeWorkflowId, input: WorkflowRunInput): WorkflowRun {
  const definition = workflowDefinition(id);
  const now = new Date().toISOString();
  const disabled = new Set(input.disabledStepIds);
  return {
    id: crypto.randomUUID(),
    workflowId: id,
    status: "queued",
    input: { ...input, batchCount: Math.max(1, Math.min(input.batchCount, 10)) },
    inputSnapshot: JSON.stringify(input),
    steps: definition.steps.map((step) => ({
      id: step.id,
      title: step.title,
      kind: step.kind,
      status: step.optional && disabled.has(step.id) ? "skipped" : "pending",
      artifactIds: [],
    })),
    activeStepIndex: 0,
    artifactIds: [],
    createdAt: now,
    updatedAt: now,
  };
}

export function artifactKind(id: CreativeWorkflowId, stepId: string): CreativeArtifactKind {
  if (id === "incubation") return "brief";
  if (id === "storyBible") return "storyBible";
  if (id === "outline") return "outline";
  if (id === "chapterProduction") return stepId === "chapter-cards" ? "chapterCards" : "chapterDraft";
  if (id === "continuityAudit") return "auditReport";
  return "polishedChapter";
}

export function validatePayload(payload: CreativeGenerationPayload, run: WorkflowRun) {
  if (!payload.title.trim() || !payload.markdown.trim()) {
    throw new Error("The model returned an incomplete artifact.");
  }
  if ((run.workflowId === "outline" || run.workflowId === "chapterProduction") && !payload.items.length) {
    throw new Error("The model returned no chapter items.");
  }
  if (run.workflowId === "chapterProduction" && run.steps[run.activeStepIndex]?.id === "chapter-cards") {
    if (payload.items.length < run.input.batchCount) {
      throw new Error(`Expected ${run.input.batchCount} chapter cards, received ${payload.items.length}.`);
    }
  }
}

export function buildCreativeContext(workspace: CreativeWorkspace): import("./types").CreativeContextOption[] {
  const values: import("./types").CreativeContextOption[] = [];
  const brief = workspace.briefs.find((item) => item.id === workspace.activeBriefId);
  if (brief) values.push({ id: `brief:${brief.id}`, label: "Creative brief", content: JSON.stringify(brief), included: true });
  const bible = workspace.storyBibles.find((item) => item.id === workspace.activeStoryBibleId);
  bible?.cards.filter((card) => card.visibility === "included").forEach((card) =>
    values.push({ id: `bible:${card.id}`, label: `Story bible · ${card.name}`, content: JSON.stringify(card), included: true }),
  );
  workspace.foreshadowing.filter((item) => item.status === "active").forEach((item) =>
    values.push({ id: `foreshadow:${item.id}`, label: `Active foreshadowing · ${item.title}`, content: JSON.stringify(item), included: true }),
  );
  workspace.characterStates.forEach((item) =>
    values.push({ id: `state:${item.id}`, label: `Character state · ${item.characterName}`, content: JSON.stringify(item), included: true }),
  );
  const selectedChapter = workspace.chapters.find((item) => item.id === workspace.selectedChapterId);
  const selectedCard = workspace.outlines.flatMap((outline) => outline.chapterCards).find((card) => card.id === selectedChapter?.cardId);
  if (selectedCard) values.push({ id: `chapter-card:${selectedCard.id}`, label: `Current chapter card · ${selectedCard.title}`, content: JSON.stringify(selectedCard), included: true });
  workspace.timeline.slice(-12).forEach((item) =>
    values.push({ id: `timeline:${item.id}`, label: `Timeline · Chapter ${item.chapterNumber}`, content: JSON.stringify(item), included: true }),
  );
  workspace.chapters.filter((chapter) => chapter.status === "accepted" && chapter.currentVersionId)
    .sort((a, b) => b.number - a.number).slice(0, 3).reverse().forEach((chapter) => {
      const version = chapter.versions.find((item) => item.id === chapter.currentVersionId);
      if (version) values.push({ id: `chapter-summary:${chapter.id}`, label: `Recent chapter summary · Chapter ${chapter.number}`, content: version.summary, included: true });
    });
  return values;
}
