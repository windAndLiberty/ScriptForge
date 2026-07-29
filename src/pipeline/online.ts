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
你现在只执行一次轻量角色改名，不分析章节、不写剧情。
为每个原著角色生成适合中国短剧、自然且有辨识度的中文姓名。姓名使用2–4个汉字，彼此不得重复，不得沿用旧名，也不得与用户已经保留的姓名重复；禁止“角色8、人物3、男主、女配、甲乙丙丁”等占位称呼，不要使用数字或身份标签。`,
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
你是“故事圣经架构师”，只建立全剧唯一事实源，不写分集、不写剧本。
必须以人物改名表为准建立 canonicalCharacters：sourceNames 保存原著姓名和能够被证据确认的别名，scriptName 只能使用新名。
同一个人不得因为称呼变化被拆成两人；不同人物不得因为身份相似被误合并。
worldRules 必须把“当前状态、直接原因、证据章节”写清楚。例如修为耗尽、灵脉损毁、被人暗算不能混为同一事实。
timeline 每个事件必须包含发生地点、原因和结果；propThreads 只收录会推动剧情或形成视觉记忆点的道具，并规划引入与兑现集。`,
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
你是连续性编辑。请只修复给出的故事圣经问题，保留有章节证据的事实；不得添加无法回溯的新关系、新设定或新事件。`,
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
必须严格使用人物改名表中的新名，输出中不得出现任何旧名。
生成恰好 ${options.episodeCount} 集；单集目标 ${options.durationSeconds} 秒；题材策略为“${options.trendPreset}”。
每一集的 sceneCount 必须由你根据本集动作节点、地点切换必要性和情绪节拍单独决定，可在 ${dynamicSceneRange.min}–${dynamicSceneRange.max} 场之间动态变化。不要机械地让所有分集场次数相同；能在一个场景完成的冲突不要硬拆，发生地点、时间或核心攻守状态改变时才切场。
允许把同一章拆成多集，但不得为凑集数编造原文没有的核心关系。每集只选择3–5个具体事实，必须发生一次可视化行动、一次阻碍升级和一次关系或信息反转。
集名必须来自本集独特动作、道具或选择，禁用“归来、真相、危机、反击”等无辨识度单词作为单独集名。`,
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
你是短剧总编剧与连续性编辑。保持有证据的核心事实，只修复相邻集重复、转场断裂、前三集无升级、道具不兑现等规划问题。`,
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
只使用以下人物新名：${resolvedCharacters.map((character) => character.targetName).join("、")}。

本集硬性可拍预算：
1. 分集规划模型已根据本集剧情决定使用 ${item.sceneCount} 场；保持这个动态规划结果；
2. 全集使用 ${budget.minDialogueLines}–${budget.maxDialogueLines} 句有效对白、${budget.spokenCharacters.min}–${budget.spokenCharacters.max} 个汉字，目标约 ${budget.spokenCharacters.target} 字；
   单句平均不超过15字，任何一句不得超过24字；长信息必须拆成“短台词—反应动作—短台词”，每场动作行至少 ${budget.minActionCharactersPerScene} 个字符；
3. 发言角色不超过 ${budget.maxSpeakingCharacters} 人；不要让所有关系人物排队报到；
4. 0–5秒直接发生钩子，随后依次完成“阻碍加码 → 主动选择 → 信息/关系反转 → 未完成行动卡点”；
5. 每场必须发生状态变化，角色要有动作、阻力和代价。禁止用回忆问答、自报家门或集体安慰代替戏剧冲突；
6. 开场钩子必须直接成为第一场动作或对白，结尾卡点必须直接成为最后一个可拍动作或台词，不得在场景外另写【冷开场】【反转】【卡点】说明；
7. 只选择本集最关键的 3–5 个原文事实完成戏剧化，其余事实留给后续集，不要把整章压缩成剧情梗概。
8. 本集只能推进分集契约中的 dominantConflict；newInformation 必须真正出现在画面或对白中，entryState 到 exitState 必须发生可见变化。

动作行不用小说腔，不得出现旧名。`;
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
          instructions: `你是短剧成稿审片员，只做低成本语义初审，不改写剧本。
以故事圣经和分集执行契约为唯一标准，检查：
1. 人物身份、关系、世界规则、地点与上一集状态是否连续；
2. 本集是否只推进一个核心冲突，且新增信息、反转和结尾卡点真正进入可拍场景；
3. 台词是否口语化、有攻守变化，是否重复解释、机械放狠话或排队发言；
4. 重要道具是否按状态使用，不能突然出现、失效或改变能力。
只有存在会影响理解、留存或拍摄的实质问题时才判定不通过；不要对文风做无关紧要的挑剔。
repairBrief 必须是可直接交给编剧执行的短指令。`,
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
这是第 ${revisionRound} 轮质量修订。必须逐条修复检查问题，重写完整场景，不要解释修改过程。
对白和动作都要有新的有效信息，不得靠重复台词、语气词或空泛动作凑字数；发言角色超限时合并功能重复的配角。`,
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
