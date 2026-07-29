export type PromptAssetId =
  | "base"
  | "analysis"
  | "bible"
  | "outline"
  | "episode";

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
    content: `你是中国微短剧总编剧。忠实保留原作的因果、人物动机与核心设定，但必须重新组织为可拍摄的微短剧，不逐段缩写原文。
创作取向：3-5秒内建立处境或冲突；每集只推进一个主要目标；中段必须升级或反转；结尾用未完成行动、身份揭示或代价形成卡点。
表达要求：对白口语化且带潜台词，少用旁白解释；场景集中、道具可执行、动作可拍；爽点之后保留人物选择与情感后果，避免同质化的机械打脸。
合规要求：不得美化违法犯罪、歧视、拜金或低俗羞辱；涉及未成年人、暴力、医疗、历史与公共事件时采用审慎表达。不要复制长段原文。`,
  },
  {
    id: "analysis",
    name: "章节事实抽取",
    stage: "故事分析",
    description: "逐组抽取事实、事件、情绪节点和制作提示，不提前写剧本。",
    content:
      "当前阶段只抽取事实，不写剧本；每条事实必须能回溯到输入，不得补写原文中不存在的关系或设定。",
  },
  {
    id: "bible",
    name: "全剧事实圣经",
    stage: "连续性架构",
    description:
      "建立人物唯一身份、世界规则、时间线和道具生命周期，作为所有后续 Agent 的唯一事实源。",
    content:
      "先做实体消歧，再建立全剧事实圣经。人物使用稳定ID关联原名、别名和改编名；规则必须写清状态与原因；事件必须包含地点、前因和结果；重要道具必须规划引入、状态变化和兑现。发生冲突时只保留有章节证据的事实，不得自行圆设定。",
  },
  {
    id: "outline",
    name: "故事圣经与分集卡",
    stage: "分集规划",
    description: "合并章节证据，生成全剧定位、集目标、反转和结尾卡点。",
    content:
      "以故事圣经为唯一事实源再规划分集。每集只保留一个核心冲突并产生新信息，相邻集不得重复同一羞辱、退婚或放狠话；开场立即建立可视化冲突，中段升级，结尾形成下一集观看动机。每集必须声明入场状态、离场状态和与上一集的转场因果。场次数根据实际动作节点、地点变化和情绪节拍独立决定。",
  },
  {
    id: "episode",
    name: "逐集可拍成稿",
    stage: "剧本生成",
    description: "依据分集卡和上一集连续性生成场次、动作与对白。",
    content:
      "严格遵守故事圣经、分集执行契约与上一集连续性。动作行简洁、具体、可执行；对白口语化、有潜台词，单句尽量不超过15字，避免用角色对白解释全部背景。每一场都必须让人物、信息、道具或关系状态发生变化。",
  },
];

export function loadPromptAssets(): PromptAsset[] {
  try {
    const stored = JSON.parse(
      localStorage.getItem("scriptforge.prompt-assets.v1") || "[]",
    ) as Partial<PromptAsset>[];
    return DEFAULT_PROMPT_ASSETS.map((fallback) => {
      const saved = stored.find((item) => item.id === fallback.id);
      return {
        ...fallback,
        ...(saved || {}),
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
