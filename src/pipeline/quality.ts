import type {
  AdaptationOptions,
  CharacterProfile,
  Episode,
  QualityMetric,
  QualityReport,
  StoryBible,
} from "../domain";
import {
  assessEpisodeScenes,
  runtimeBudget,
} from "./episodeBudget";
import { isPlausibleSourceCharacterName } from "./characters";
import {
  validateEpisodeContracts,
  validateStoryBible,
} from "./storyBible";

function metric(
  id: string,
  label: string,
  score: number,
  detail: string,
): QualityMetric {
  return {
    id,
    label,
    score: Math.round(Math.max(0, Math.min(100, score))),
    detail,
    level: score >= 85 ? "good" : score >= 65 ? "warn" : "bad",
  };
}

export function evaluateScript(
  episodes: Episode[],
  characters: CharacterProfile[],
  options: AdaptationOptions,
  storyBible?: StoryBible,
): QualityReport {
  const allContent = episodes.map((episode) => episode.content).join("\n");
  const leaks = characters.filter(
    (character) =>
      isPlausibleSourceCharacterName(character.sourceName) &&
      character.sourceName !== character.targetName &&
      allContent.includes(character.sourceName),
  );
  const sceneCount = episodes.reduce(
    (total, episode) => total + episode.scenes.length,
    0,
  );
  const expectedScenes = episodes.reduce(
    (total, episode) =>
      total + (episode.plannedSceneCount || episode.scenes.length),
    0,
  );
  const missingHooks = episodes.filter(
    (episode) => !episode.openingHook || !episode.endHook,
  ).length;
  const dialogueCount = episodes.reduce(
    (total, episode) =>
      total +
      episode.scenes.reduce(
        (sceneTotal, scene) => sceneTotal + scene.dialogue.length,
        0,
      ),
    0,
  );
  const budget = runtimeBudget(options);
  const completeness = episodes.map((episode) =>
    assessEpisodeScenes(episode.scenes, {
      ...options,
      scenesPerEpisode:
        episode.plannedSceneCount || episode.scenes.length,
    }),
  );
  const weakEpisodes = completeness
    .map((item, index) => ({ ...item, episode: index + 1 }))
    .filter((item) => !item.passed);
  const spokenCharacters = completeness.reduce(
    (total, item) => total + item.spokenCharacters,
    0,
  );
  const scriptCharacters = completeness.reduce(
    (total, item) => total + item.scriptCharacters,
    0,
  );
  const averageCompleteness =
    completeness.reduce((total, item) => total + item.score, 0) /
    Math.max(1, completeness.length);
  const estimatedSeconds = completeness.reduce(
    (total, item) => total + item.runtime.estimatedSeconds,
    0,
  );
  const targetSeconds = episodes.length * options.durationSeconds;
  const durationFit = Math.min(
    estimatedSeconds / Math.max(1, targetSeconds),
    targetSeconds / Math.max(1, estimatedSeconds),
  );
  const bibleCheck = storyBible
    ? validateStoryBible(storyBible, characters)
    : { passed: true, issues: [] };
  const contracts = episodes.flatMap((episode) =>
    episode.contract ? [episode.contract] : [],
  );
  const contractCheck =
    storyBible && contracts.length === episodes.length
      ? validateEpisodeContracts(contracts, storyBible)
      : {
          passed: !storyBible,
          issues: storyBible ? ["部分分集缺少连续性执行契约"] : [],
        };
  const continuityIssues = [
    ...bibleCheck.issues,
    ...contractCheck.issues,
  ];
  const semanticAudits = episodes.flatMap((episode) =>
    episode.semanticAudit ? [episode.semanticAudit] : [],
  );
  const semanticIssues = semanticAudits.flatMap((audit, index) =>
    audit.passed
      ? []
      : audit.issues.map((issue) => `第${index + 1}集：${issue}`),
  );
  const semanticScore = semanticAudits.length
    ? semanticAudits.reduce((total, audit) => total + audit.score, 0) /
      semanticAudits.length
    : 100;
  const riskyPatterns = [
    /未成年人.{0,12}(?:性|裸|酒)/,
    /(?:吸毒|赌博).{0,12}(?:爽|致富|成功)/,
    /(?:地域|性别|职业)歧视/,
    /详细(?:犯罪|制毒|自杀)方法/,
  ].filter((pattern) => pattern.test(allContent));

  const metrics = [
    metric(
      "rename",
      "人物改名一致性",
      leaks.length ? Math.max(20, 100 - leaks.length * 18) : 100,
      leaks.length
        ? `发现 ${leaks.length} 个旧名残留：${leaks.map((item) => item.sourceName).join("、")}`
        : `已检查 ${characters.length} 组人物映射，未发现旧名残留`,
    ),
    metric(
      "structure",
      "分集与场次结构",
      Math.min(
        100,
        (Math.min(sceneCount, expectedScenes) /
          Math.max(1, Math.max(sceneCount, expectedScenes))) *
          100,
      ),
      `${episodes.length} 集 / 实际 ${sceneCount} 场，模型动态规划 ${expectedScenes} 场`,
    ),
    metric(
      "hooks",
      "开场与结尾钩子",
      100 - (missingHooks / Math.max(1, episodes.length)) * 100,
      missingHooks ? `${missingHooks} 集缺少有效钩子` : "每集均有冷开场和结尾悬念",
    ),
    metric(
      "dialogue",
      "对白可拍性",
      Math.min(
        100,
        ((dialogueCount / Math.max(1, episodes.length * budget.minDialogueLines)) *
          0.45 +
          (spokenCharacters /
            Math.max(1, episodes.length * budget.spokenCharacters.min)) *
            0.55) *
          100,
      ),
      `共 ${dialogueCount} 句 / ${spokenCharacters} 字有效对白；目标每集至少 ${budget.minDialogueLines} 句 / ${budget.spokenCharacters.min} 字`,
    ),
    metric(
      "completeness",
      "成稿完整度",
      averageCompleteness,
      weakEpisodes.length
        ? `${weakEpisodes.length} 集低于完整成稿线：${weakEpisodes
            .slice(0, 5)
            .map((item) => `第${item.episode}集 ${item.score}分`)
            .join("、")}`
        : `全部分集达到动作、对白、角色聚焦和节拍密度要求`,
    ),
    metric(
      "duration",
      "目标时长贴合",
      durationFit * 100,
      `表演时长模型预计平均 ${Math.round(estimatedSeconds / Math.max(1, episodes.length))} 秒；目标 ${options.durationSeconds} 秒（平均 ${Math.round(spokenCharacters / Math.max(1, episodes.length))} 字对白）`,
    ),
    metric(
      "continuity",
      "全剧连续性与去重复",
      continuityIssues.length
        ? Math.max(20, 100 - continuityIssues.length * 12)
        : 100,
      continuityIssues.length
        ? continuityIssues.slice(0, 4).join("；")
        : storyBible
          ? "人物身份、世界规则、转场因果、相邻集冲突与道具线均已通过"
          : "旧项目未包含故事圣经；建议重新生成以启用跨集连续性检查",
    ),
    metric(
      "semantic",
      "叙事语义初审",
      semanticScore,
      semanticAudits.length
        ? semanticIssues.length
          ? semanticIssues.slice(0, 4).join("；")
          : "人物动机、攻守变化、契约兑现与可拍钩子均已通过"
        : "离线模式未执行语义初审",
    ),
    metric(
      "compliance",
      "内容风险初筛",
      riskyPatterns.length ? 62 : 96,
      riskyPatterns.length
        ? `命中 ${riskyPatterns.length} 条需人工复核的高风险表达`
        : "未命中内置高风险模式；上线前仍需人工审片与备案判断",
    ),
  ];
  const weights: Record<string, number> = {
    rename: 1,
    structure: 1,
    hooks: 1,
    dialogue: 1,
    completeness: 3,
    duration: 2,
    continuity: 3,
    semantic: 2,
    compliance: 1,
  };
  const totalWeight = metrics.reduce(
    (total, item) => total + (weights[item.id] || 1),
    0,
  );
  let score = Math.round(
    metrics.reduce(
      (total, item) => total + item.score * (weights[item.id] || 1),
      0,
    ) / totalWeight,
  );
  if (weakEpisodes.length) {
    score = Math.min(score, Math.round(averageCompleteness + 15));
  }
  const warnings = [
    ...(leaks.length ? ["人物旧名仍有残留，建议执行一致性修复。"] : []),
    ...(riskyPatterns.length ? ["内容初筛命中风险项，请进行人工合规复核。"] : []),
    ...(weakEpisodes.length
      ? [
          `${weakEpisodes.length} 集未达到完整成稿线，应扩写动作、冲突对白或减少同场发言角色后重写。`,
        ]
      : []),
    ...(continuityIssues.length
      ? [`连续性检查发现 ${continuityIssues.length} 项问题：${continuityIssues.slice(0, 3).join("；")}`]
      : []),
    ...(semanticIssues.length
      ? [`语义初审仍有 ${semanticIssues.length} 项问题：${semanticIssues.slice(0, 3).join("；")}`]
      : []),
    "AI 生成内容须人工复核；正式制作、备案和播出规则以主管部门及平台最新要求为准。",
  ];

  return {
    score,
    metrics,
    warnings,
    passed:
      score >= 80 &&
      leaks.length === 0 &&
      weakEpisodes.length === 0 &&
      continuityIssues.length === 0 &&
      semanticIssues.length === 0,
  };
}
