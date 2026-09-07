export type PromptAssetId =
  | "base"
  | "analysis"
  | "bible"
  | "outline"
  | "episode"
  | "storyboard";

export interface PromptAsset {
  id: PromptAssetId;
  name: string;
  stage: string;
  description: string;
  content: string;
}

export const DEFAULT_PROMPT_ASSETS: PromptAsset[] = [
  {
    id: "base",
    name: "总编剧系统规范",
    stage: "全管线",
    description: "控制忠实度、短剧节奏、可拍性和内容合规的基础提示词。",
    content: `You are the head writer for a vertical micro-drama. Preserve the source work's causality, character motivations, and core rules, while reorganizing it into a shootable drama rather than summarizing paragraphs.
Creative direction: establish a situation or conflict within 3–5 seconds; advance one dominant goal per episode; escalate or reverse in the middle; end on an unfinished action, identity reveal, or meaningful cost.
Expression: use conversational dialogue with subtext and minimal expository narration; concentrate locations, keep props executable, and make action shootable. Preserve character choice and emotional consequence after each payoff instead of repeating mechanical humiliation.
Safety: never glorify crime, discrimination, materialism, or degrading vulgarity. Treat minors, violence, medicine, history, and public events carefully. Do not reproduce long passages from the source.`,
  },
  {
    id: "analysis",
    name: "章节事实抽取",
    stage: "故事分析",
    description: "逐组抽取事实、事件、情绪节点和制作提示，不提前写剧本。",
    content:
      "At this stage, extract facts only and do not draft a screenplay. Every fact must trace to the input; never invent relationships or rules absent from the source.",
  },
  {
    id: "bible",
    name: "全剧事实圣经",
    stage: "连续性架构",
    description:
      "建立人物唯一身份、世界规则、时间线和道具生命周期，作为所有后续 Agent 的唯一事实源。",
    content:
      "Resolve entity identity before building the canonical story bible. Use stable IDs to connect source names, aliases, and adapted names. Rules must record state and cause; events must include location, cause, and effect; important props must track introduction, state changes, and payoff. When evidence conflicts, retain only chapter-supported facts and never patch the canon by invention.",
  },
  {
    id: "outline",
    name: "故事圣经与分集卡",
    stage: "分集规划",
    description: "合并章节证据，生成全剧定位、集目标、反转和结尾卡点。",
    content:
      "Use the story bible as the sole factual source when planning episodes. Keep one core conflict and introduce new information in every episode. Adjacent episodes must not repeat the same humiliation, breakup, or threat. Establish a visual conflict immediately, escalate in the middle, and end with a reason to continue. Declare entry state, exit state, and causal transition from the previous episode. Determine scene count from actual action beats, location changes, and emotional rhythm.",
  },
  {
    id: "episode",
    name: "逐集可拍成稿",
    stage: "剧本生成",
    description: "依据分集卡和上一集连续性生成场次、动作与对白。",
    content:
      "Follow the story bible, episode contract, and previous-episode continuity exactly. Keep action concise, specific, and executable. Dialogue must be conversational and contain subtext; avoid using dialogue to explain the entire backstory. Every scene must change a character, information, prop, or relationship state.",
  },
  {
    id: "storyboard",
    name: "分镜与多媒体制作包",
    stage: "分镜制作",
    description: "控制镜头拆分、构图、运镜、声音设计和图像提示词，但不改变已批准的故事。",
    content:
      "Convert only the approved screenplay into production-ready shots. Preserve facts, characters, locations, outcomes, screen direction, props, wardrobe, and visual anchors. Specify shot size, camera movement, composition, performance action, sound, continuity, and production notes. Image and negative prompts must be English for broad image-model compatibility.",
  },
];

const LEGACY_DEFAULT_HASHES: Partial<Record<PromptAssetId, string>> = {
  base: "c50c670d",
  analysis: "1a67053",
  bible: "d94b8f4b",
  outline: "9e9766b5",
  episode: "ba8dda74",
};

function contentHash(value: string) {
  let hash = 2166136261;
  for (const character of value) {
    hash ^= character.codePointAt(0) || 0;
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

export function loadPromptAssets(): PromptAsset[] {
  try {
    const stored = JSON.parse(
      localStorage.getItem("scriptforge.prompt-assets.v1") || "[]",
    ) as Partial<PromptAsset>[];
    return DEFAULT_PROMPT_ASSETS.map((fallback) => {
      const saved = stored.find((item) => item.id === fallback.id);
      const legacyDefault =
        typeof saved?.content === "string" &&
        contentHash(saved.content) === LEGACY_DEFAULT_HASHES[fallback.id];
      return {
        ...fallback,
        ...(legacyDefault ? {} : saved || {}),
        id: fallback.id,
      };
    });
  } catch {
    return DEFAULT_PROMPT_ASSETS;
  }
}

export function promptContent(
  assets: PromptAsset[] | undefined,
  id: PromptAssetId,
) {
  return (
    assets?.find((asset) => asset.id === id)?.content ||
    DEFAULT_PROMPT_ASSETS.find((asset) => asset.id === id)?.content ||
    ""
  );
}
