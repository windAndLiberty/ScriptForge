import { beforeEach, describe, expect, it, vi } from "vitest";
import { compileCreativePrompt, defaultPromptOverride } from "./prompts";
import { advanceRun, approveRun, createRun, setChapterCandidate } from "./service";
import { emptyCreativeWorkspace, type CreativeGenerationPayload, type CreativeWorkspace } from "./types";
import { WORKFLOW_DEFINITIONS, startWorkflow } from "./workflows";

const files = new Map<string, unknown>();
const model = vi.fn(async (payload: { name: string }) => {
  const count = 3;
  const cards = Array.from({ length: count }, (_, index) => ({ kind: "chapter", name: `Chapter ${index + 1}`, summary: `Summary ${index + 1}`, content: payload.name.includes("draft") ? `Complete draft ${index + 1}` : `Card ${index + 1}`, details: ["Goal", "Conflict", "Reveal", "Hook", "Beat"] }));
  return { title: "Volume One", summary: "Arc", markdown: "# Artifact", items: cards } satisfies CreativeGenerationPayload;
});

beforeEach(() => {
  files.clear(); model.mockClear();
  Object.defineProperty(globalThis, "window", { configurable: true, value: { desktopAPI: {
    writeProjectJson: async ({ category, itemId, value }: { category: string; itemId: string; value: unknown }) => { const path = `${category}/${itemId}.json`; files.set(path, structuredClone(value)); return path; },
    readProjectJson: async ({ relativePath }: { relativePath: string }) => structuredClone(files.get(relativePath)),
    writeProjectText: async ({ category, itemId, content }: { category: string; itemId: string; content: string }) => { const path = `${category}/${itemId}.md`; files.set(path, content); return path; },
    readProjectText: async ({ relativePath }: { relativePath: string }) => String(files.get(relativePath) || ""),
    callStructured: model,
  } } });
});

describe("creative workflow engine", () => {
  it("registers all six fixed workflows and caps batches at ten", () => {
    expect(WORKFLOW_DEFINITIONS.map((item) => item.id)).toEqual(["incubation", "storyBible", "outline", "chapterProduction", "continuityAudit", "chapterPolish"]);
    const run = startWorkflow("chapterProduction", { seed: "", instruction: "", batchCount: 99, selectedChapterIds: [], parameters: {}, disabledStepIds: [], excludedContextIds: [] });
    expect(run.input.batchCount).toBe(10);
  });

  it("confirms a three-card batch once, then creates non-destructive chapter candidates", async () => {
    let workspace: CreativeWorkspace = emptyCreativeWorkspace();
    let { run, workspace: createdWorkspace } = await createRun("project", workspace, "chapterProduction", { seed: "A new arc", instruction: "", batchCount: 3, selectedChapterIds: [], parameters: { targetWords: "2000" }, disabledStepIds: [], excludedContextIds: [] });
    workspace = createdWorkspace;
    ({ run, workspace } = await advanceRun({ projectId: "project", workspace, run, outputLanguage: "English", hasModel: true }));
    expect(run.status).toBe("waitingForApproval");
    expect(run.steps[run.activeStepIndex].id).toBe("approve-cards");
    ({ run, workspace } = await approveRun("project", workspace, run));
    ({ run, workspace } = await advanceRun({ projectId: "project", workspace, run, outputLanguage: "English", hasModel: true }));
    expect(run.steps[run.activeStepIndex].id).toBe("approve-drafts");
    expect(workspace.chapters).toHaveLength(3);
    expect(workspace.chapters.every((chapter) => chapter.status === "review" && !chapter.currentVersionId && chapter.candidateVersionId)).toBe(true);
    expect(model).toHaveBeenCalledTimes(2);
    await expect(approveRun("project", workspace, run)).rejects.toThrow("Review each candidate chapter");
    for (const chapter of workspace.chapters) workspace = await setChapterCandidate("project", workspace, chapter.id, true);
    ({ run, workspace } = await approveRun("project", workspace, run));
    ({ run, workspace } = await advanceRun({ projectId: "project", workspace, run, outputLanguage: "English", hasModel: true }));
    expect(run.status).toBe("completed");
    expect(workspace.chapters.every((chapter) => chapter.status === "accepted" && chapter.currentVersionId)).toBe(true);
  });

  it("waits for model configuration without losing the current step", async () => {
    const created = await createRun("project", emptyCreativeWorkspace(), "incubation", { seed: "Idea", instruction: "", batchCount: 1, selectedChapterIds: [], parameters: {}, disabledStepIds: [], excludedContextIds: [] });
    const result = await advanceRun({ projectId: "project", ...created, outputLanguage: "English", hasModel: false });
    expect(result.run.status).toBe("waitingForModel");
    expect(result.run.steps[result.run.activeStepIndex].kind).toBe("model");
  });
});

describe("creative prompt compiler", () => {
  it("applies system, workflow, project, and run layers and excludes context", () => {
    const compiled = compileCreativePrompt({ workflowId: "incubation", workflowOverride: defaultPromptOverride("incubation"), projectInstruction: "Project style", runInstruction: "Run preference", variables: { seed: "Idea", outputLanguage: "English" }, context: [{ id: "a", label: "Included", content: "Fact A", included: true }, { id: "b", label: "Excluded", content: "Fact B", included: true }], excludedContextIds: ["b"] });
    expect(compiled.instructions).toContain("Project style");
    expect(compiled.instructions).toContain("Run preference");
    expect(compiled.input).toContain("Fact A");
    expect(compiled.input).not.toContain("Fact B");
    expect(compiled.snapshot.contextLabels).toEqual(["Included"]);
  });

  it("preflights missing template variables", () => {
    const override = defaultPromptOverride("incubation"); override.instruction = "Use {{missing}}";
    expect(() => compileCreativePrompt({ workflowId: "incubation", workflowOverride: override, projectInstruction: "", runInstruction: "", variables: { seed: "" }, context: [], excludedContextIds: [] })).toThrow("Missing prompt variables");
  });
});

