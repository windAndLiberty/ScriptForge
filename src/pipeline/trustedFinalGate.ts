import type {
  AdaptationOptions,
  CharacterProfile,
  Episode,
  PipelinePhase,
  QualityGateTraceStep,
  ScriptScene,
  StoryBible,
} from "../domain";
import {
  assessEpisodeScenes,
} from "./episodeBudget";
import { callModelStage, type StructuredCaller } from "./modelRouter";
import { renderEpisode } from "./offline";
import { evaluateScript } from "./quality";
import {
  buildEpisodeAuditWindows,
  buildQualityGateReport,
  episodeRepairQueue,
  normalizeWindowAuditIssues,
  type RawQualityGateIssue,
  type WindowAuditResult,
} from "./qualityGate";
import { compactStoryBible } from "./storyBible";

const stringArray = { type: "array", items: { type: "string" } };
const issueCategoryEnum = [
  "source_fidelity",
  "continuity",
  "character",
  "pacing",
  "hook",
  "dialogue",
  "production",
  "compliance",
];
const issueSeverityEnum = ["blocker", "major", "minor"];

function seriesAuditSchema(episodeCount: number) {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      passed: { type: "boolean" },
      score: { type: "integer", minimum: 0, maximum: 100 },
      issues: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            id: { type: "string" },
            severity: { type: "string", enum: issueSeverityEnum },
            category: { type: "string", enum: issueCategoryEnum },
            episodeNumbers: {
              type: "array",
              minItems: 1,
              items: {
                type: "integer",
                minimum: 1,
                maximum: episodeCount,
              },
            },
            evidence: { type: "string", minLength: 1 },
            repairInstruction: { type: "string", minLength: 1 },
          },
          required: [
            "id",
            "severity",
            "category",
            "episodeNumbers",
            "evidence",
            "repairInstruction",
          ],
        },
      },
    },
    required: ["passed", "score", "issues"],
  };
}

const episodeRepairSchema = {
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
          action: { type: "string", minLength: 1 },
          dialogue: {
            type: "array",
            minItems: 1,
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                speaker: { type: "string", minLength: 1 },
                text: { type: "string", minLength: 1 },
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

type GeneratedScene = Omit<ScriptScene, "id">;

interface EpisodeAudit {
  passed: boolean;
  score: number;
  issues: string[];
  repairBrief: string[];
}

function auditPayload(episode: Episode) {
  return {
    number: episode.number,
    title: episode.title,
    openingHook: episode.openingHook,
    objective: episode.objective,
    reversal: episode.reversal,
    endHook: episode.endHook,
    sourceChapterIds: episode.sourceChapterIds,
    contract: episode.contract,
    runtime: episode.runtime,
    scenes: episode.scenes,
  };
}

function auditInstructions() {
  return `你是竖屏短剧交付终审，不参与创作，只依据给定证据登记实质缺陷。
逐集与跨集检查：
1. 原著事实与故事圣经：不得新增无证据的核心身份、关系、能力、因果；
2. 连续性：上一集出口状态必须能推出下一集入口，人物、地点、时间、伤势、道具状态不能跳变；
3. 推进与去重复：相邻集不得重复同一羞辱、退婚、身份确认或放狠话，每集必须产生新信息和不可逆状态变化；
4. 60/90秒可拍性：钩子进入前5秒，单集聚焦一个冲突，台词有攻守而非轮流解释，结尾是正在发生的动作卡点；
5. 角色声音与动机：同一角色的目标、称谓和行为逻辑稳定，配角不能仅排队报到；
6. 制作与合规：避免无法落地的大场面堆叠，标记必须人工复核的高风险内容。

严重级别：
- blocker：事实、人物或连续性错误会让观众无法理解，或存在明显合规风险；
- major：影响留存、节奏或拍摄，必须修复；
- minor：不阻断交付的润色建议。

每条问题必须引用具体集数与可见证据，并给出可执行的短修复指令。没有实质问题时 issues 必须为空，禁止为了显得严格而虚构问题。`;
}

async function auditEpisodeCandidate(params: {
  callStructured: StructuredCaller;
  storyBible: StoryBible;
  episode: Episode;
  previousEpisode?: Episode;
}) {
  const { callStructured, storyBible, episode, previousEpisode } = params;
  return callModelStage<EpisodeAudit>(
    callStructured,
    "episode_semantic_audit",
    {
      instructions: `你是短剧修订复验员，只判断候选版本是否真正修复问题且没有制造新问题。
检查故事圣经、分集契约、上一集出口状态、场景动作、台词攻守、可拍钩子和道具状态。
只有存在影响理解、留存或拍摄的实质问题时才判定不通过。`,
      input: `【故事圣经】${JSON.stringify(compactStoryBible(storyBible))}
【上一集】${JSON.stringify(previousEpisode ? auditPayload(previousEpisode) : null)}
【本集契约】${JSON.stringify(episode.contract)}
【候选场景】${JSON.stringify(episode.scenes)}`,
      name: `episode_${episode.number}_final_semantic_audit`,
      schema: episodeAuditSchema,
    },
  );
}

export async function runTrustedFinalGate(params: {
  episodes: Episode[];
  characters: CharacterProfile[];
  options: AdaptationOptions;
  storyBible: StoryBible;
  callStructured: StructuredCaller;
  onPhase?: (phase: PipelinePhase, detail: string, progress: number) => void;
}) {
  const {
    characters,
    options,
    storyBible,
    callStructured,
    onPhase,
  } = params;
  let episodes = params.episodes.map((episode) => structuredClone(episode));
  const trace: QualityGateTraceStep[] = [];
  const preliminaryQuality = evaluateScript(
    episodes,
    characters,
    options,
    storyBible,
  );
  trace.push({
    id: "deterministic-precheck",
    stage: "deterministic_precheck",
    status: preliminaryQuality.passed ? "passed" : "failed",
    episodeNumbers: episodes.map((episode) => episode.number),
    detail: `程序预检 ${preliminaryQuality.score} 分；${preliminaryQuality.passed ? "达到硬指标" : "仍有硬指标未达标"}`,
  });

  const runWindowAudits = async (
    currentEpisodes: Episode[],
    verification: boolean,
  ) => {
    const windows = buildEpisodeAuditWindows(currentEpisodes);
    const audits = await Promise.all(
      windows.map(async (window) => {
        const result = await callModelStage<WindowAuditResult>(
          callStructured,
          "series_quality_audit",
          {
            instructions: auditInstructions(),
            input: `【故事圣经】${JSON.stringify(compactStoryBible(storyBible))}
【本窗口之前一集】${JSON.stringify(
              currentEpisodes.find(
                (episode) => episode.number === window.episodeNumbers[0] - 1,
              )
                ? auditPayload(
                    currentEpisodes.find(
                      (episode) =>
                        episode.number === window.episodeNumbers[0] - 1,
                    )!,
                  )
                : null,
            )}
【重叠审片窗口】${JSON.stringify(window.episodes.map(auditPayload))}
【本窗口之后一集】${JSON.stringify(
              currentEpisodes.find(
                (episode) =>
                  episode.number ===
                  (window.episodeNumbers.at(-1) || 0) + 1,
              )
                ? auditPayload(
                    currentEpisodes.find(
                      (episode) =>
                        episode.number ===
                        (window.episodeNumbers.at(-1) || 0) + 1,
                    )!,
                  )
                : null,
            )}`,
            name: verification
              ? `series_quality_verify_${window.id}`
              : `series_quality_audit_${window.id}`,
            schema: seriesAuditSchema(currentEpisodes.length),
          },
        );
        trace.push({
          id: `${verification ? "verify" : "audit"}-${window.id}`,
          stage: verification ? "verification" : "window_audit",
          status: result.passed ? "passed" : "failed",
          episodeNumbers: window.episodeNumbers,
          detail: `${verification ? "复验" : "初审"} ${result.score} 分；登记 ${(result.issues || []).length} 项问题`,
        });
        return result;
      }),
    );
    return {
      windows,
      audits,
      issues: normalizeWindowAuditIssues(audits, currentEpisodes.length),
    };
  };

  onPhase?.("quality", "正在并行执行跨集连续性与留存审片", 90);
  const initialReview = await runWindowAudits(episodes, false);
  const repairQueue = episodeRepairQueue(initialReview.issues);
  let repairAttempts = 0;
  let acceptedRepairs = 0;

  for (const episodeNumber of repairQueue) {
    const episodeIndex = episodes.findIndex(
      (episode) => episode.number === episodeNumber,
    );
    if (episodeIndex < 0) continue;
    const currentEpisode = episodes[episodeIndex];
    const previousEpisode = episodes[episodeIndex - 1];
    const nextEpisode = episodes[episodeIndex + 1];
    const issues = initialReview.issues.filter((issue) =>
      issue.episodeNumbers.includes(episodeNumber),
    );
    if (!issues.length) continue;

    repairAttempts += 1;
    onPhase?.(
      "quality",
      `终审发现第 ${episodeNumber} 集存在实质问题，正在定向修复`,
      92 + Math.min(4, Math.round((repairAttempts / repairQueue.length) * 4)),
    );
    const revised = await callModelStage<{ scenes: GeneratedScene[] }>(
      callStructured,
      "series_quality_repair",
      {
        instructions: `你是短剧交付修订编剧。只修复问题台账中的实质缺陷，保持本集分集契约、原著事实、人物新名和动态场次数。
必须输出完整场景，不解释修改过程。不得通过增加旁白、重复台词、凭空设定或删除关键事实来规避问题。
修复后仍须符合目标时长、对白密度、发言角色数和动作节拍预算。`,
        input: `【故事圣经】${JSON.stringify(compactStoryBible(storyBible))}
【上一集】${JSON.stringify(previousEpisode ? auditPayload(previousEpisode) : null)}
【待修复本集】${JSON.stringify(auditPayload(currentEpisode))}
【下一集】${JSON.stringify(nextEpisode ? auditPayload(nextEpisode) : null)}
【问题台账】${JSON.stringify(issues)}
请定向重写第 ${episodeNumber} 集的完整 scenes。`,
        name: `episode_${episodeNumber}_final_repair`,
        schema: episodeRepairSchema,
      },
    );

    const candidateScenes = revised.scenes.map((scene, index) => ({
      ...scene,
      id: `episode-${episodeNumber}-scene-${index + 1}`,
    }));
    const candidateCompleteness = assessEpisodeScenes(candidateScenes, {
      ...options,
      scenesPerEpisode:
        currentEpisode.plannedSceneCount || candidateScenes.length,
    });
    const candidate: Episode = {
      ...currentEpisode,
      scenes: candidateScenes,
      runtime: candidateCompleteness.runtime,
      content: "",
    };
    const candidateAudit = await auditEpisodeCandidate({
      callStructured,
      storyBible,
      episode: candidate,
      previousEpisode,
    });
    candidate.semanticAudit = {
      score: candidateAudit.score,
      passed: candidateAudit.passed,
      issues: candidateAudit.issues,
    };
    candidate.content = renderEpisode(candidate, options.durationSeconds);

    const currentCompleteness = assessEpisodeScenes(currentEpisode.scenes, {
      ...options,
      scenesPerEpisode:
        currentEpisode.plannedSceneCount || currentEpisode.scenes.length,
    });
    const currentComposite =
      currentCompleteness.score * 0.6 +
      (currentEpisode.semanticAudit?.score || 0) * 0.4;
    const candidateComposite =
      candidateCompleteness.score * 0.6 + candidateAudit.score * 0.4;
    const accepted =
      candidateCompleteness.passed &&
      candidateAudit.passed &&
      candidateComposite >= currentComposite - 2;
    if (accepted) {
      episodes[episodeIndex] = candidate;
      acceptedRepairs += 1;
    }
    trace.push({
      id: `repair-episode-${episodeNumber}`,
      stage: "targeted_repair",
      status: accepted ? "accepted" : "rejected",
      episodeNumbers: [episodeNumber],
      detail: accepted
        ? `候选版本通过程序复算与独立语义复验，综合 ${Math.round(candidateComposite)} 分`
        : `候选版本未同时通过硬指标与语义复验，保留原稿`,
    });
  }

  const finalReview = repairAttempts
    ? await runWindowAudits(episodes, true)
    : initialReview;
  const finalQuality = evaluateScript(
    episodes,
    characters,
    options,
    storyBible,
  );
  trace.push({
    id: "deterministic-verification",
    stage: "verification",
    status: finalQuality.passed ? "passed" : "failed",
    episodeNumbers: episodes.map((episode) => episode.number),
    detail: `修复后程序复算 ${finalQuality.score} 分`,
  });
  const gate = buildQualityGateReport({
    deterministicScore: finalQuality.score,
    deterministicPassed: finalQuality.passed,
    initialIssues: initialReview.issues,
    finalIssues: finalReview.issues,
    finalAuditsPassed: finalReview.audits.every((audit) => audit.passed),
    auditedWindows:
      initialReview.windows.length +
      (repairAttempts ? finalReview.windows.length : 0),
    repairAttempts,
    acceptedRepairs,
    trace,
  });
  finalQuality.gate = gate;
  finalQuality.passed =
    finalQuality.passed && gate.status === "passed";
  if (gate.status !== "passed") {
    finalQuality.warnings.unshift(
      `可信终审仍有 ${gate.openIssueCount} 项开放问题，已阻止自动标记为可交付。`,
    );
  }
  return { episodes, quality: finalQuality };
}
