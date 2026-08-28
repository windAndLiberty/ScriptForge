import type {
  AdaptationOptions,
  AdaptationResult,
  CharacterProfile,
  Episode,
  EpisodeContract,
  NovelDocument,
  PipelinePhase,
  ScriptScene,
  StoryBible,
} from "../domain";
import {
  assertValidRenameMap,
  isGenericCharacterName,
  resolveModelCharacterNames,
  type ModelCharacterRename,
} from "./characters";
import { groupChapters } from "./ingest";
import { renderEpisode } from "./offline";
import {
  promptContent,
  type PromptAsset,
} from "../promptAssets";
import {
  assessEpisodeScenes,
  runtimeBudget,
  sceneCountRange,
} from "./episodeBudget";
import {
  compactStoryBible,
  validateEpisodeContracts,
  validateStoryBible,
} from "./storyBible";
import {
  callModelStage,
  type StructuredCaller,
} from "./modelRouter";
import { runTrustedFinalGate } from "./trustedFinalGate";

export type { StructuredCaller } from "./modelRouter";

const stringArray = { type: "array", items: { type: "string" } };
const chapterAnalysisSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: { type: "string" },
    facts: stringArray,
    keyEvents: stringArray,
    emotionalBeats: stringArray,
    productionNotes: stringArray,
  },
  required: ["summary", "facts", "keyEvents", "emotionalBeats", "productionNotes"],
};

const episodeAuditSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    passed: { type: "boolean" },
    score: { type: "integer", minimum: 0, maximum: 100 },
    issues: stringArray,
    repairBrief: stringArray,
  },
  required: ["passed", "score", "issues", "repairBrief"],
};

const evidenceIds = {
  type: "array",
  items: { type: "string" },
};

const storyBibleSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    premise: { type: "string" },
    canonicalCharacters: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          id: { type: "string" },
          sourceNames: stringArray,
          scriptName: { type: "string" },
          role: { type: "string" },
          relationships: stringArray,
          evidenceChapterIds: evidenceIds,
        },
        required: [
          "id",
          "sourceNames",
          "scriptName",
          "role",
          "relationships",
          "evidenceChapterIds",
        ],
      },
    },
    worldRules: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          id: { type: "string" },
          subject: { type: "string" },
          fact: { type: "string" },
          cause: { type: "string" },
          evidenceChapterIds: evidenceIds,
        },
        required: ["id", "subject", "fact", "cause", "evidenceChapterIds"],
      },
    },
    propThreads: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          id: { type: "string" },
          name: { type: "string" },
          dramaticFunction: { type: "string" },
          introducedEpisode: { type: "integer", minimum: 1 },
          payoffEpisode: { type: "integer", minimum: 1 },
          currentState: { type: "string" },
          evidenceChapterIds: evidenceIds,
        },
        required: [
          "id",
          "name",
          "dramaticFunction",
          "introducedEpisode",
          "payoffEpisode",
          "currentState",
          "evidenceChapterIds",
        ],
      },
    },
    timeline: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          id: { type: "string" },
          order: { type: "integer", minimum: 1 },
          location: { type: "string" },
          time: { type: "string" },
          participants: stringArray,
          cause: { type: "string" },
          event: { type: "string" },
          effect: { type: "string" },
          evidenceChapterIds: evidenceIds,
        },
        required: [
          "id",
          "order",
          "location",
          "time",
          "participants",
          "cause",
          "event",
          "effect",
          "evidenceChapterIds",
        ],
      },
    },
  },
  required: [
    "premise",
    "canonicalCharacters",
    "worldRules",
    "propThreads",
    "timeline",
  ],
};

function characterNamingSchema(characterCount: number) {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      renames: {
        type: "array",
        minItems: characterCount,
        maxItems: characterCount,
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            sourceName: { type: "string", minLength: 2 },
            targetName: { type: "string", minLength: 2, maxLength: 4 },
          },
          required: ["sourceName", "targetName"],
        },
      },
    },
    required: ["renames"],
  };
}

function outlineSchema(
  episodeCount: number,
  sceneRange: { min: number; max: number },
) {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      logline: { type: "string" },
      genre: { type: "string" },
      themes: stringArray,
      sourceFacts: stringArray,
      episodes: {
        type: "array",
        minItems: episodeCount,
        maxItems: episodeCount,
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            number: { type: "integer" },
            title: { type: "string" },
            sourceChapterIds: stringArray,
            sceneCount: {
              type: "integer",
              minimum: sceneRange.min,
              maximum: sceneRange.max,
            },
            openingHook: { type: "string" },
            objective: { type: "string" },
            reversal: { type: "string" },
            endHook: { type: "string" },
            dominantConflict: { type: "string" },
            newInformation: stringArray,
            visualHook: { type: "string" },
            transitionFromPrevious: { type: "string" },
            activePropThreads: stringArray,
            entryState: { type: "string" },
            exitState: { type: "string" },
          },
          required: [
            "number",
            "title",
            "sourceChapterIds",
            "sceneCount",
            "openingHook",
            "objective",
            "reversal",
            "endHook",
            "dominantConflict",
            "newInformation",
            "visualHook",
            "transitionFromPrevious",
            "activePropThreads",
            "entryState",
            "exitState",
          ],
        },
      },
    },
    required: ["logline", "genre", "themes", "sourceFacts", "episodes"],
  };
}

export function episodeTransportSchema() {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      scenes: {
        type: "array",
        minItems: 1,
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            heading: { type: "string", minLength: 1 },
            location: { type: "string", minLength: 1 },
            action: {
              type: "string",
              minLength: 1,
            },
            dialogue: {
              type: "array",
              minItems: 1,
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  speaker: { type: "string", minLength: 1 },
                  text: {
                    type: "string",
                    minLength: 1,
                  },
                },
                required: ["speaker", "text"],
              },
            },
          },
          required: ["heading", "location", "action", "dialogue"],
        },
      },
    },
    required: ["scenes"],
  };
}

interface ChapterAnalysis {
  summary: string;
  facts: string[];
  keyEvents: string[];
  emotionalBeats: string[];
  productionNotes: string[];
}

interface EpisodeAudit {
  passed: boolean;
  score: number;
  issues: string[];
  repairBrief: string[];
}

interface OutlineResult {
  logline: string;
  genre: string;
  themes: string[];
  sourceFacts: string[];
  episodes: Array<
    Omit<
      Episode,
      "id" | "scenes" | "content" | "plannedSceneCount" | "contract" | "runtime"
    > &
      EpisodeContract & {
      sceneCount: number;
      }
  >;
}

type GeneratedScene = Omit<ScriptScene, "id">;

function contractFromOutline(
  item: OutlineResult["episodes"][number],
): EpisodeContract {
  return {
    dominantConflict: item.dominantConflict,
    newInformation: item.newInformation,
    visualHook: item.visualHook,
    transitionFromPrevious: item.transitionFromPrevious,
    activePropThreads: item.activePropThreads,
    entryState: item.entryState,
    exitState: item.exitState,
  };
}

export async function generateModelCharacterNames(params: {
  document: NovelDocument;
  characters: CharacterProfile[];
  options: AdaptationOptions;
  promptAssets?: PromptAsset[];
  callStructured: StructuredCaller;
}): Promise<CharacterProfile[]> {
  const {
    document,
    characters,
    options,
    promptAssets,
    callStructured,
  } = params;
  const pendingCharacters = characters.filter(
    (character) =>
      !["model", "manual"].includes(character.nameSource || "") ||
      !character.targetName.trim() ||
      isGenericCharacterName(character.targetName),
  );
  if (!pendingCharacters.length) return characters;

  const preservedCharacters = characters.filter(
    (character) => !pendingCharacters.includes(character),
  );
  const preservedNames = preservedCharacters.map(
    (character) => character.targetName,
  );
  const compactContexts = pendingCharacters.map((character) => {
    const offset = document.rawText.indexOf(character.sourceName);
    const start = Math.max(0, offset - 48);
    const context =
      offset >= 0
        ? document.rawText.slice(
            start,
            offset + character.sourceName.length + 72,
          )
        : "";
    return {
      sourceName: character.sourceName,
      role: character.role,
      traits: character.traits,
      context,
    };
  });
  const naming = await callModelStage<{ renames: ModelCharacterRename[] }>(
    callStructured,
    "character_naming",
    {
    instructions: `${promptContent(promptAssets, "base")}
Perform one lightweight character-renaming pass only. Do not analyze chapters or draft plot.
Give every source character a natural, distinctive name suitable for the target drama. Names must be unique, must not reuse source names, and must not conflict with names retained by the user. Never use numbered roles, generic labels such as Male Lead or Supporting Woman, letters, digits, or identity tags as names.`,
    input: `【作品】${document.title}
【题材】${options.genre}
【语气】${options.tone}
【用户已保留姓名】${preservedNames.join("、") || "无"}
【待命名角色与极短上下文】
${JSON.stringify(compactContexts)}
只返回一一对应的改名表。`,
    name: "character_naming",
    schema: characterNamingSchema(pendingCharacters.length),
    },
  );
  const generated = resolveModelCharacterNames(
    pendingCharacters,
    naming.renames,
    preservedNames,
  );
  const generatedById = new Map(
    generated.map((character) => [character.id, character]),
  );
  return characters.map(
    (character) => generatedById.get(character.id) || character,
  );
}

export async function runOnlinePipeline(params: {
  document: NovelDocument;
  characters: CharacterProfile[];
  options: AdaptationOptions;
  promptAssets?: PromptAsset[];
  callStructured: StructuredCaller;
  onCharacters?: (characters: CharacterProfile[]) => void;
  onPhase?: (phase: PipelinePhase, detail: string, progress: number) => void;
}): Promise<AdaptationResult> {
  const {
    document,
    characters,
    options,
    promptAssets,
    callStructured,
    onCharacters,
    onPhase,
  } = params;
  const baseInstructions = promptContent(promptAssets, "base");
  let resolvedCharacters = characters;
  if (
    characters.some(
      (character) =>
        !["model", "manual"].includes(character.nameSource || "") ||
        !character.targetName.trim() ||
        isGenericCharacterName(character.targetName),
    )
  ) {
    onPhase?.("characters", "正在由模型轻量生成角色新名", 6);
    resolvedCharacters = await generateModelCharacterNames({
      document,
      characters,
      options,
      promptAssets,
      callStructured,
    });
    onCharacters?.(resolvedCharacters);
  }
  assertValidRenameMap(resolvedCharacters);
  const analysisGroups = groupChapters(document.chapters, Math.ceil(document.chapters.length / 2));
  const analyses: ChapterAnalysis[] = [];

  onPhase?.("analysis", "正在逐组抽取故事事实与情绪节点", 12);
  for (let index = 0; index < analysisGroups.length; index += 1) {
    const group = analysisGroups[index];
    const input = group
      .map(
        (chapter) =>
          `[${chapter.id}｜第${chapter.index}章 ${chapter.title}]\n${chapter.content.slice(0, 16000)}`,
      )
      .join("\n\n");
    analyses.push(
      await callModelStage<ChapterAnalysis>(
        callStructured,
        "chapter_analysis",
        {
        instructions: `${baseInstructions}\n${promptContent(promptAssets, "analysis")}`,
        input,
        name: "chapter_analysis",
        schema: chapterAnalysisSchema,
        },
      ),
    );
    onPhase?.(
      "analysis",
      `已分析 ${Math.min((index + 1) * 2, document.chapters.length)} / ${document.chapters.length} 章`,
      12 + Math.round(((index + 1) / analysisGroups.length) * 24),
    );
  }

  const renameMap = resolvedCharacters
    .map(
      (character) =>
        `${character.sourceName}→${character.targetName}（${character.role}；${character.traits.join("、")}）`,
    )
    .join("\n");
  onPhase?.("bible", "正在建立人物、规则、道具与时间线圣经", 39);
  let storyBible = await callModelStage<StoryBible>(
    callStructured,
    "story_bible",
    {
    instructions: `${baseInstructions}
${promptContent(promptAssets, "bible")}
You are the story-bible architect. Build the production's sole factual source; do not plan episodes or draft screenplay.
Build canonicalCharacters from the rename map: sourceNames keeps source names and evidence-supported aliases, while scriptName uses only the approved new name.
Never split one person because their form of address changes, and never merge different people because their roles look similar.
Every worldRule must state current condition, direct cause, and evidence chapters. Distinct conditions cannot be conflated.
Every timeline event must include location, cause, and result. propThreads includes only props that advance plot or create a visual memory point, with planned introduction and payoff episodes.`,
    input: `【作品】${document.title}
【人物改名表】
${renameMap}
【章节事实分析】
${JSON.stringify(analyses)}
请建立可供所有后续 Agent 读取的故事圣经。`,
    name: "story_bible",
    schema: storyBibleSchema,
    },
  );
  let bibleCheck = validateStoryBible(storyBible, resolvedCharacters);
  if (!bibleCheck.passed) {
    onPhase?.("bible", "故事圣经存在冲突，正在定向校正", 42);
    storyBible = await callModelStage<StoryBible>(
      callStructured,
      "story_bible_repair",
      {
      instructions: `${baseInstructions}
${promptContent(promptAssets, "bible")}
You are a continuity editor. Repair only the listed story-bible defects, preserve chapter-supported facts, and never add relationships, rules, or events that cannot be traced to evidence.`,
      input: `【人物改名表】
${renameMap}
【章节事实分析】
${JSON.stringify(analyses)}
【待修复故事圣经】
${JSON.stringify(storyBible)}
【程序发现的问题】
${bibleCheck.issues.join("；")}
输出修复后的完整故事圣经。`,
      name: "story_bible_repair",
      schema: storyBibleSchema,
      },
    );
    bibleCheck = validateStoryBible(storyBible, resolvedCharacters);
  }

  onPhase?.("outline", "正在根据故事圣经规划分集契约", 45);
  const dynamicSceneRange = sceneCountRange(options.durationSeconds);
  let outline = await callModelStage<OutlineResult>(
    callStructured,
    "episode_outline",
    {
    instructions: `${baseInstructions}
${promptContent(promptAssets, "outline")}
Use only approved new names from the rename map; no source name may appear in output.
Generate exactly ${options.episodeCount} episodes targeting ${options.durationSeconds} seconds each, using the strategy "${options.trendPreset}".
Determine each episode's sceneCount independently from action beats, necessary location changes, and emotional rhythm, within ${dynamicSceneRange.min}–${dynamicSceneRange.max}. Do not mechanically use the same count. Keep a conflict in one scene when possible; cut only when location, time, or the core attack/defense state changes.
One chapter may span several episodes, but never invent a core relationship to fill the count. Select only 3–5 concrete facts per episode and include a visible action, an escalated obstacle, and a relationship or information reversal.
Derive each title from a distinctive action, prop, or choice in that episode; avoid generic standalone titles such as Return, Truth, Crisis, or Counterattack.`,
    input: `【作品】${document.title}
【人物改名表】
${renameMap}
【唯一事实源：故事圣经】
${JSON.stringify(compactStoryBible(storyBible))}
为每集同时建立执行契约：dominantConflict 只能有一个且相邻集不得重复；newInformation 必须是本集新增；visualHook 必须能在前5秒拍出来；transitionFromPrevious 必须解释时间、地点或人物为何发生变化；entryState 必须承接上一集 exitState。
前三集必须完成“强视觉处境—公开冲突—能力/身份或阴谋实证”的连续升级，但不得机械重复羞辱、退婚或放狠话。重要道具必须通过 activePropThreads 在规划的集数内兑现。
请输出全局故事定位和分集卡。`,
    name: "episode_outline",
    schema: outlineSchema(options.episodeCount, dynamicSceneRange),
    },
  );
  let contractCheck = validateEpisodeContracts(
    outline.episodes.map(contractFromOutline),
    storyBible,
  );
  if (!contractCheck.passed) {
    onPhase?.("outline", "分集存在重复或断裂，正在修复分集契约", 50);
    outline = await callModelStage<OutlineResult>(
      callStructured,
      "episode_outline_repair",
      {
      instructions: `${baseInstructions}
${promptContent(promptAssets, "outline")}
You are the head writer and continuity editor. Preserve evidence-supported core facts and repair only planning defects such as adjacent repetition, broken transitions, no escalation across the first three episodes, or missing prop payoffs.`,
      input: `【故事圣经】
${JSON.stringify(compactStoryBible(storyBible))}
【待修复分集规划】
${JSON.stringify(outline)}
【程序发现的问题】
${contractCheck.issues.join("；")}
必须输出恰好 ${options.episodeCount} 集完整分集规划，每集 ${dynamicSceneRange.min}–${dynamicSceneRange.max} 场。`,
      name: "episode_outline_repair",
      schema: outlineSchema(options.episodeCount, dynamicSceneRange),
      },
    );
    contractCheck = validateEpisodeContracts(
      outline.episodes.map(contractFromOutline),
      storyBible,
    );
  }

  const outlines = outline.episodes.slice(0, options.episodeCount);
  const episodes: Episode[] = [];
  onPhase?.("drafting", "正在按连续性上下文逐集生成", 55);
  for (let index = 0; index < outlines.length; index += 1) {
    const item = outlines[index];
    const budget = runtimeBudget({
      ...options,
      scenesPerEpisode: item.sceneCount,
    });
    const contract = contractFromOutline(item);
    const episodeInstructions = `${baseInstructions}
${promptContent(promptAssets, "episode")}
Use only these approved character names: ${resolvedCharacters.map((character) => character.targetName).join(", ")}.

Hard production budget for this episode:
1. Keep the dynamically planned ${item.sceneCount} scenes.
2. Use ${budget.minDialogueLines}–${budget.maxDialogueLines} effective dialogue lines and ${budget.spokenCharacters.min}–${budget.spokenCharacters.max} spoken characters, targeting about ${budget.spokenCharacters.target}. Keep individual lines concise. Break long information into short dialogue, reaction action, and short dialogue. Each scene needs at least ${budget.minActionCharactersPerScene} action characters.
3. Use no more than ${budget.maxSpeakingCharacters} speaking characters; do not make every relationship character report in sequence.
4. Put the hook directly in seconds 0–5, then move through obstacle escalation, active choice, information or relationship reversal, and an unfinished-action cliffhanger.
5. Every scene must visibly change state through action, resistance, and cost. Never replace conflict with memory Q&A, self-introduction, or group reassurance.
6. The opening hook must be the first shootable action or line, and the ending hook must be the final shootable action or line. Do not add out-of-scene labels for cold open, reversal, or cliffhanger.
7. Dramatize only the 3–5 most important source facts and leave the rest for later episodes; never compress an entire chapter into a plot summary.
8. Advance only the contract's dominantConflict. newInformation must appear on screen or in dialogue, and entryState must visibly change into exitState.

Use production-facing action rather than novelistic prose. No source character names may appear.`;
    const sourceChapters = document.chapters.filter((chapter) =>
      item.sourceChapterIds.includes(chapter.id),
    );
    const previousContinuity = episodes.at(-1)
      ? {
          previousEndHook: episodes.at(-1)?.endHook,
          previousLastScene: episodes.at(-1)?.scenes.at(-1),
          previousExitState: episodes.at(-1)?.contract?.exitState,
          previousLocation: episodes.at(-1)?.scenes.at(-1)?.location,
        }
      : null;
    let generated = await callModelStage<{ scenes: GeneratedScene[] }>(
      callStructured,
      "episode_draft",
      {
      instructions: episodeInstructions,
      input: `【全局故事】${outline.logline}
【唯一事实源：故事圣经】${JSON.stringify(compactStoryBible(storyBible))}
【本集分集卡】${JSON.stringify(item)}
【本集执行契约】${JSON.stringify(contract)}
【上一集连续性】${JSON.stringify(previousContinuity)}
【对应原文】${sourceChapters
        .map((chapter) => `[${chapter.id}]\n${chapter.content.slice(0, 12000)}`)
        .join("\n")}
请生成第${item.number}集场景。`,
      name: `episode_${item.number}`,
      schema: episodeTransportSchema(),
      },
    );
    const episodeOptions = {
      ...options,
      scenesPerEpisode: item.sceneCount,
    };
    let completeness = assessEpisodeScenes(generated.scenes, episodeOptions);
    const auditScenes = (scenes: GeneratedScene[]) =>
      callModelStage<EpisodeAudit>(
        callStructured,
        "episode_semantic_audit",
        {
          instructions: `You are a screenplay semantic reviewer performing a low-cost first pass; do not rewrite the screenplay.
Use only the story bible and episode contract to check:
1. continuity of identity, relationships, world rules, location, and prior-episode state;
2. whether the episode advances one core conflict and puts new information, reversal, and the ending hook into shootable scenes;
3. whether dialogue is conversational and adversarial rather than repetitive exposition, mechanical threats, or a queue of speakers;
4. whether important props follow their tracked state instead of appearing, failing, or changing ability without cause.
Fail only for material problems affecting comprehension, retention, or production. Do not nitpick inconsequential style.
Every repairBrief must be a short, directly executable instruction for the writer.`,
          input: `【故事圣经】${JSON.stringify(compactStoryBible(storyBible))}
【本集执行契约】${JSON.stringify(contract)}
【上一集连续性】${JSON.stringify(previousContinuity)}
【本集场景】${JSON.stringify(scenes)}`,
          name: `episode_${item.number}_semantic_audit`,
          schema: episodeAuditSchema,
        },
      );
    let semanticAudit = await auditScenes(generated.scenes);
    for (
      let revisionRound = 1;
      revisionRound <= 2 &&
      (!completeness.passed || !semanticAudit.passed);
      revisionRound += 1
    ) {
      onPhase?.(
        "drafting",
        `第 ${item.number} 集未达到成稿线，正在进行第 ${revisionRound} 轮定向重写`,
        55 + Math.round(((index + 0.5) / outlines.length) * 32),
      );
      const revised = await callModelStage<{ scenes: GeneratedScene[] }>(
        callStructured,
        "episode_repair",
        {
        instructions: `${episodeInstructions}
This is quality revision round ${revisionRound}. Repair every listed issue and return complete rewritten scenes without explaining the revision process.
Dialogue and action must add meaningful information. Never pad length with repeated lines, filler sounds, or empty action. When the speaking-character limit is exceeded, consolidate supporting roles with duplicate functions.`,
        input: `【全局故事】${outline.logline}
【唯一事实源：故事圣经】${JSON.stringify(compactStoryBible(storyBible))}
【本集分集卡】${JSON.stringify(item)}
【本集执行契约】${JSON.stringify(contract)}
【上一集连续性】${JSON.stringify(previousContinuity)}
【对应原文】${sourceChapters
          .map((chapter) => `[${chapter.id}]\n${chapter.content.slice(0, 12000)}`)
          .join("\n")}
【初稿】${JSON.stringify(generated)}
【程序检查问题】${completeness.issues.join("；")}
【语义初审问题】${semanticAudit.issues.join("；")}
【修复指令】${semanticAudit.repairBrief.join("；")}
【实测数据】对白 ${completeness.spokenCharacters} 字，动作与对白 ${completeness.scriptCharacters} 字，共 ${completeness.dialogueLines} 句，${completeness.speakingCharacters} 个发言角色，预计 ${completeness.runtime.estimatedSeconds} 秒；本轮必须控制在 ${budget.minDialogueLines}–${budget.maxDialogueLines} 句、${budget.spokenCharacters.min}–${budget.spokenCharacters.max} 字，发言角色不超过 ${budget.maxSpeakingCharacters} 人，并让预计时长接近 ${options.durationSeconds} 秒。
请从头重写第${item.number}集。`,
        name:
          revisionRound === 1
            ? `episode_${item.number}_rewrite`
            : `episode_${item.number}_rewrite_${revisionRound}`,
        schema: episodeTransportSchema(),
        },
      );
      const revisedCompleteness = assessEpisodeScenes(
        revised.scenes,
        episodeOptions,
      );
      const revisedAudit = await auditScenes(revised.scenes);
      const currentComposite =
        completeness.score * 0.6 + semanticAudit.score * 0.4;
      const revisedComposite =
        revisedCompleteness.score * 0.6 + revisedAudit.score * 0.4;
      if (revisedComposite >= currentComposite) {
        generated = revised;
        completeness = revisedCompleteness;
        semanticAudit = revisedAudit;
      }
    }
    const {
      sceneCount,
      dominantConflict: _dominantConflict,
      newInformation: _newInformation,
      visualHook: _visualHook,
      transitionFromPrevious: _transitionFromPrevious,
      activePropThreads: _activePropThreads,
      entryState: _entryState,
      exitState: _exitState,
      ...episodeCard
    } = item;
    const episode: Episode = {
      ...episodeCard,
      id: `episode-${item.number}`,
      plannedSceneCount: sceneCount,
      contract,
      runtime: completeness.runtime,
      semanticAudit: {
        score: semanticAudit.score,
        passed: semanticAudit.passed,
        issues: semanticAudit.issues,
      },
      scenes: generated.scenes.map((scene, sceneIndex) => ({
        ...scene,
        id: `episode-${item.number}-scene-${sceneIndex + 1}`,
      })),
      content: "",
    };
    episode.content = renderEpisode(episode, options.durationSeconds);
    episodes.push(episode);
    onPhase?.(
      "drafting",
      `已完成 ${index + 1} / ${outlines.length} 集`,
      55 + Math.round(((index + 1) / outlines.length) * 32),
    );
  }

  onPhase?.("quality", "正在进入可信终审与定向修复闭环", 89);
  const trustedResult = await runTrustedFinalGate({
    episodes,
    characters: resolvedCharacters,
    options,
    storyBible,
    callStructured,
    onPhase,
  });
  return {
    logline: outline.logline,
    genre: outline.genre,
    themes: outline.themes,
    sourceFacts: outline.sourceFacts,
    storyBible,
    episodes: trustedResult.episodes,
    quality: trustedResult.quality,
    generatedAt: new Date().toISOString(),
    mode: "online",
  };
}
