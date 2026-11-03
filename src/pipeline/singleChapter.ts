import type {
  CharacterProfile,
  SingleChapterStoryBoard,
  SingleChapterWorkflow,
} from "../domain";

export const FIRST_PASS_PROMPT =
  "你是一个专业的小说推文作者，请你优化这段小说，使用“爆款开头+结尾留钩”的结构，不利于观众停留的剧情酌情删掉。";

export const SECOND_PASS_PROMPT =
  "你是一个专业的视频推文博主，请你优化这段文案，用作视频推文，“爆款开头+结尾留钩”的结构，不适合做成视频的内容适当进行改编。";

export const REVISION_PROMPT =
  "你是一名专业短剧编剧。用户的每次输入都代表对当前剧本的修改要求，不要回答问题或解释修改过程。请严格遵守故事板、人物改名表和用户要求，返回修改后的完整剧本。";

export const SINGLE_CHAPTER_SCRIPT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    script: { type: "string", minLength: 1 },
  },
  required: ["script"],
} as const;

export const CHARACTER_NAMING_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    characters: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          sourceName: { type: "string", minLength: 1 },
          targetName: { type: "string", minLength: 1 },
          role: { type: "string" },
        },
        required: ["sourceName", "targetName", "role"],
      },
    },
  },
  required: ["characters"],
} as const;

export function emptySingleChapterWorkflow(
  selectedChapterId?: string,
): SingleChapterWorkflow {
  return {
    selectedChapterId,
    renameConfirmed: false,
    stage: "characters",
    storyBoard: {
      worldName: "",
      worldBackground: "",
      coreEntries: "",
      forbiddenWords: "",
    },
    versions: [],
    messages: [],
  };
}

export function normalizeSingleChapterWorkflow(
  value: SingleChapterWorkflow | null | undefined,
  selectedChapterId?: string,
): SingleChapterWorkflow {
  const fallback = emptySingleChapterWorkflow(selectedChapterId);
  if (!value || typeof value !== "object") return fallback;
  const storyBoard = value.storyBoard || fallback.storyBoard;
  const versions = Array.isArray(value.versions)
    ? value.versions.filter(
        (version) =>
          version &&
          typeof version.id === "string" &&
          typeof version.content === "string",
      )
    : [];
  const activeVersionId = versions.some(
    (version) => version.id === value.activeVersionId,
  )
    ? value.activeVersionId
    : versions.at(-1)?.id;
  const validStages: SingleChapterWorkflow["stage"][] = [
    "characters",
    "ready",
    "first_pass",
    "second_pass",
    "review",
    "failed",
  ];
  return {
    selectedChapterId: value.selectedChapterId || selectedChapterId,
    renameConfirmed: Boolean(value.renameConfirmed),
    stage: validStages.includes(value.stage) ? value.stage : "characters",
    storyBoard: {
      worldName: String(storyBoard.worldName || "").slice(0, 80),
      worldBackground: String(storyBoard.worldBackground || "").slice(0, 3000),
      coreEntries: String(storyBoard.coreEntries || "").slice(0, 200),
      forbiddenWords: String(storyBoard.forbiddenWords || "").slice(0, 100),
    },
    firstPass:
      typeof value.firstPass === "string" ? value.firstPass : undefined,
    versions,
    activeVersionId,
    comparison: value.comparison,
    messages: Array.isArray(value.messages) ? value.messages : [],
  };
}

export function formatRenameMap(characters: CharacterProfile[]) {
  return characters
    .map((character) => `${character.sourceName} → ${character.targetName}`)
    .join("\n");
}

export function formatStoryBoard(storyBoard: SingleChapterStoryBoard) {
  return [
    `世界设定名称：${storyBoard.worldName || "未填写"}`,
    `世界背景：\n${storyBoard.worldBackground || "未填写"}`,
    `核心词条：${storyBoard.coreEntries || "未填写"}`,
    `禁止输出词语：${storyBoard.forbiddenWords || "无"}`,
  ].join("\n\n");
}

export function activeSingleChapterScript(
  workflow: SingleChapterWorkflow | null | undefined,
) {
  if (!workflow?.activeVersionId) return "";
  return (
    workflow.versions.find(
      (version) => version.id === workflow.activeVersionId,
    )?.content || ""
  );
}

export async function runFixedSingleChapterPipeline(args: {
  chapter: string;
  constraints: string;
  call: (instructions: string, input: string, name: string) => Promise<string>;
  onStage?: (stage: "first_pass" | "second_pass") => void;
}) {
  args.onStage?.("first_pass");
  const firstPass = await args.call(
    FIRST_PASS_PROMPT,
    `${args.constraints}\n\n【单章原文】\n${args.chapter}`,
    "single_chapter_first_pass",
  );
  args.onStage?.("second_pass");
  const finalScript = await args.call(
    SECOND_PASS_PROMPT,
    `${args.constraints}\n\n【第一次调用输出】\n${firstPass}`,
    "single_chapter_second_pass",
  );
  return { firstPass, finalScript };
}
