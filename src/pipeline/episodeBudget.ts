import type {
  AdaptationOptions,
  EpisodeRuntimeEstimate,
  ScriptScene,
} from "../domain";

export interface EpisodeRuntimeBudget {
  durationSeconds: number;
  recommendedScenes: number;
  spokenCharacters: {
    min: number;
    target: number;
    max: number;
  };
  scriptCharacters: {
    min: number;
    target: number;
    max: number;
  };
  minDialogueLines: number;
  maxDialogueLines: number;
  minDialogueLinesPerScene: number;
  maxDialogueCharactersPerLine: number;
  minDialogueCharactersPerLine: number;
  minActionCharactersPerScene: number;
  maxSpeakingCharacters: number;
  sourceCharactersPerEpisode: number;
}

export interface EpisodeCompleteness {
  score: number;
  passed: boolean;
  issues: string[];
  spokenCharacters: number;
  scriptCharacters: number;
  dialogueLines: number;
  speakingCharacters: number;
  weakSceneCount: number;
  runtime: EpisodeRuntimeEstimate;
}

export function recommendedScenes(durationSeconds: number) {
  if (durationSeconds <= 60) return 2;
  if (durationSeconds <= 90) return 3;
  if (durationSeconds <= 120) return 4;
  return 5;
}

export function sceneCountRange(durationSeconds: number) {
  if (durationSeconds <= 60) return { min: 1, max: 3 };
  if (durationSeconds <= 90) return { min: 1, max: 4 };
  if (durationSeconds <= 120) return { min: 2, max: 5 };
  return { min: 2, max: 6 };
}

export function runtimeBudget(
  options: Pick<AdaptationOptions, "durationSeconds" | "scenesPerEpisode">,
): EpisodeRuntimeBudget {
  const duration = options.durationSeconds;
  const sceneCount = Math.max(1, options.scenesPerEpisode);
  const minDialogueLines = Math.max(sceneCount * 3, Math.round(duration / 5));
  const maxDialogueLines = Math.max(
    minDialogueLines + 3,
    Math.round(duration / 3.3),
  );
  const minDialogueLinesPerScene = Math.ceil(
    minDialogueLines / sceneCount,
  );
  const spokenMinimum = Math.round(duration * 2.15);
  const spokenTarget = Math.round(duration * 2.7);
  const spokenMaximum = Math.round(duration * 3.25);
  const scriptMinimum = Math.round(duration * 3.7);
  return {
    durationSeconds: duration,
    recommendedScenes: recommendedScenes(duration),
    spokenCharacters: {
      min: spokenMinimum,
      target: spokenTarget,
      max: spokenMaximum,
    },
    scriptCharacters: {
      min: scriptMinimum,
      target: Math.round(duration * 4.8),
      max: Math.round(duration * 6.2),
    },
    minDialogueLines,
    maxDialogueLines,
    minDialogueLinesPerScene,
    minDialogueCharactersPerLine: 2,
    maxDialogueCharactersPerLine: duration <= 60 ? 18 : 22,
    minActionCharactersPerScene: Math.max(
      24,
      Math.ceil((scriptMinimum - spokenMinimum) / sceneCount),
    ),
    maxSpeakingCharacters: Math.min(5, Math.max(3, Math.ceil(duration / 45) + 2)),
    sourceCharactersPerEpisode: Math.round(duration * 18),
  };
}

export function recommendedEpisodeCount(
  sourceCharacters: number,
  durationSeconds: number,
) {
  return Math.max(
    1,
    Math.ceil(
      sourceCharacters /
        runtimeBudget({
          durationSeconds,
          scenesPerEpisode: recommendedScenes(durationSeconds),
        }).sourceCharactersPerEpisode,
    ),
  );
}

export function readableCharacters(value: string) {
  return value.match(/[\p{L}\p{N}]/gu)?.length || 0;
}

function punctuationPauses(value: string) {
  const strong = value.match(/[。！？!?…]/g)?.length || 0;
  const weak = value.match(/[，、；：,;:]/g)?.length || 0;
  return strong * 0.22 + weak * 0.1;
}

function actionBeatCount(value: string) {
  if (!value.trim()) return 0;
  const explicitBeats = value
    .split(/[。！？!?；;\n]+/)
    .map((item) => item.trim())
    .filter(Boolean).length;
  const actionVerbs =
    value.match(
      /(?:走|冲|退|跪|抬|转|抓|扔|摔|拔|推|拉|按|点|燃|灭|亮|黑|笑|哭|看|盯|递|接|挡|劈|刺|震|响|开|关|落|起|停|撕|烧|倒|撞|握|松|藏|露|挥|闪)/g,
    )?.length || 0;
  return Math.max(1, Math.min(12, Math.max(explicitBeats, Math.ceil(actionVerbs / 2))));
}

export function estimateEpisodeRuntime(
  scenes: Array<
    Pick<ScriptScene, "heading" | "location" | "action" | "dialogue">
  >,
): EpisodeRuntimeEstimate {
  const dialogueLines = scenes.flatMap((scene) => scene.dialogue);
  const spokenCharacters = dialogueLines.reduce(
    (total, line) => total + readableCharacters(line.text),
    0,
  );
  const speechSeconds =
    spokenCharacters / 4.2 +
    dialogueLines.reduce(
      (total, line) => total + punctuationPauses(line.text),
      0,
    );
  const actionBeats = scenes.reduce(
    (total, scene) => total + actionBeatCount(scene.action),
    0,
  );
  const performanceSeconds =
    dialogueLines.length * 0.3 + actionBeats * 0.85;
  const transitionSeconds = Math.max(0, scenes.length - 1) * 1.2;
  const longDialogueLines = dialogueLines.filter(
    (line) => readableCharacters(line.text) > 18,
  ).length;
  return {
    estimatedSeconds: Math.round(
      (speechSeconds + performanceSeconds + transitionSeconds) * 10,
    ) / 10,
    speechSeconds: Math.round(speechSeconds * 10) / 10,
    performanceSeconds: Math.round(performanceSeconds * 10) / 10,
    transitionSeconds: Math.round(transitionSeconds * 10) / 10,
    dialogueLines: dialogueLines.length,
    spokenCharacters,
    longDialogueLines,
    actionBeats,
  };
}

export function assessEpisodeScenes(
  scenes: Array<
    Pick<ScriptScene, "heading" | "location" | "action" | "dialogue">
  >,
  options: Pick<AdaptationOptions, "durationSeconds" | "scenesPerEpisode">,
): EpisodeCompleteness {
  const budget = runtimeBudget(options);
  const runtime = estimateEpisodeRuntime(scenes);
  const dialogueLines = scenes.reduce(
    (total, scene) => total + scene.dialogue.length,
    0,
  );
  const spokenCharacters = scenes.reduce(
    (total, scene) =>
      total +
      scene.dialogue.reduce(
        (lineTotal, line) => lineTotal + readableCharacters(line.text),
        0,
      ),
    0,
  );
  const actionCharacters = scenes.reduce(
    (total, scene) =>
      total +
      readableCharacters(scene.action) +
      readableCharacters(scene.heading) +
      readableCharacters(scene.location),
    0,
  );
  const scriptCharacters = spokenCharacters + actionCharacters;
  const speakers = new Set(
    scenes.flatMap((scene) =>
      scene.dialogue.map((line) => line.speaker.trim()).filter(Boolean),
    ),
  );
  const weakSceneCount = scenes.filter(
    (scene) =>
      scene.dialogue.length < budget.minDialogueLinesPerScene ||
      readableCharacters(scene.action) <
        Math.max(
          24,
          Math.round(budget.minActionCharactersPerScene * 0.55),
        ),
  ).length;
  const sceneDialogueCounts = scenes.map((scene) => scene.dialogue.length);
  const largestSceneShare =
    Math.max(0, ...sceneDialogueCounts) / Math.max(1, dialogueLines);

  const issues: string[] = [];
  let score = 100;
  const proportionalPenalty = (
    actual: number,
    target: number,
    maximumPenalty: number,
  ) => {
    const deficitRatio =
      Math.max(0, target - actual) / Math.max(1, target);
    if (!deficitRatio) return 0;
    return Math.max(
      1,
      Math.round(
        maximumPenalty * Math.min(1, deficitRatio / 0.35),
      ),
    );
  };
  if (scenes.length !== options.scenesPerEpisode) {
    issues.push(`场次数为 ${scenes.length}，必须为 ${options.scenesPerEpisode} 场`);
    score -= 30;
  }
  if (spokenCharacters < budget.spokenCharacters.min) {
    issues.push(
      `有效对白仅 ${spokenCharacters} 字，至少需要 ${budget.spokenCharacters.min} 字`,
    );
    score -= proportionalPenalty(
      spokenCharacters,
      budget.spokenCharacters.min,
      24,
    );
  }
  if (spokenCharacters > budget.spokenCharacters.max) {
    issues.push(
      `有效对白 ${spokenCharacters} 字，超过 ${options.durationSeconds} 秒建议上限 ${budget.spokenCharacters.max} 字`,
    );
    score -= proportionalPenalty(
      budget.spokenCharacters.max,
      spokenCharacters,
      18,
    );
  }
  if (scriptCharacters < budget.scriptCharacters.min) {
    issues.push(
      `动作与对白合计仅 ${scriptCharacters} 字，至少需要 ${budget.scriptCharacters.min} 字`,
    );
    score -= proportionalPenalty(
      scriptCharacters,
      budget.scriptCharacters.min,
      18,
    );
  }
  if (dialogueLines < budget.minDialogueLines) {
    issues.push(
      `仅 ${dialogueLines} 句对白，至少需要 ${budget.minDialogueLines} 句`,
    );
    score -= 16;
  }
  if (dialogueLines > budget.maxDialogueLines) {
    issues.push(
      `共有 ${dialogueLines} 句对白，超过建议上限 ${budget.maxDialogueLines} 句`,
    );
    score -= Math.min(16, (dialogueLines - budget.maxDialogueLines) * 2);
  }
  if (runtime.longDialogueLines) {
    issues.push(
      `${runtime.longDialogueLines} 句对白超过18字，应拆短或改成反应动作`,
    );
    score -= Math.min(14, runtime.longDialogueLines * 2);
  }
  if (weakSceneCount) {
    issues.push(`${weakSceneCount} 场缺少足量动作或交锋对白`);
    score -= weakSceneCount * 8;
  }
  if (speakers.size > budget.maxSpeakingCharacters) {
    issues.push(
      `本集有 ${speakers.size} 个发言角色，60–180 秒短剧应聚焦在 ${budget.maxSpeakingCharacters} 个以内`,
    );
    score -= (speakers.size - budget.maxSpeakingCharacters) * 6;
  }
  if (scenes.length > 1 && largestSceneShare > 0.72) {
    issues.push("对白过度集中在单一场次，前后节拍失衡");
    score -= 10;
  }
  const minimumRuntime = options.durationSeconds * 0.82;
  const maximumRuntime = options.durationSeconds * 1.15;
  if (runtime.estimatedSeconds < minimumRuntime) {
    issues.push(
      `预计仅 ${runtime.estimatedSeconds} 秒，未达到 ${options.durationSeconds} 秒完整成稿节拍`,
    );
    score -= proportionalPenalty(
      runtime.estimatedSeconds,
      minimumRuntime,
      20,
    );
  }
  if (runtime.estimatedSeconds > maximumRuntime) {
    issues.push(
      `预计 ${runtime.estimatedSeconds} 秒，超过 ${options.durationSeconds} 秒可拍上限`,
    );
    score -= proportionalPenalty(
      maximumRuntime,
      runtime.estimatedSeconds,
      20,
    );
  }

  const normalizedScore = Math.max(0, Math.round(score));
  return {
    score: normalizedScore,
    passed: normalizedScore >= 85,
    issues,
    spokenCharacters,
    scriptCharacters,
    dialogueLines,
    speakingCharacters: speakers.size,
    weakSceneCount,
    runtime,
  };
}
