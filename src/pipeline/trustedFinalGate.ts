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
  return `You are the final delivery reviewer for a vertical micro-drama. Do not participate in creative writing; register only material defects supported by supplied evidence.
Check within and across episodes:
1. source facts and story bible: no unsupported core identity, relationship, ability, or causality;
2. continuity: an episode's exit state must support the next entry state; character, location, time, injury, and prop state cannot jump;
3. progression and repetition: adjacent episodes cannot repeat the same humiliation, breakup, identity confirmation, or threat; each episode must add information and an irreversible state change;
4. 60/90-second shootability: hook in the first five seconds, one conflict per episode, adversarial dialogue rather than rotating exposition, and an ending built from an action in progress;
5. character voice and motivation: stable goals, forms of address, and behavior logic; supporting characters cannot merely queue to appear;
6. production and safety: avoid unshootable spectacle stacking and flag high-risk content requiring human review.

Severity:
- blocker: a factual, character, continuity, or safety defect that prevents comprehension or delivery;
- major: a retention, pacing, or production defect that must be repaired;
- minor: a non-blocking polish suggestion.

Every issue must cite episode numbers and visible evidence and include a short executable repair instruction. When there is no material defect, issues must be empty. Never invent issues to appear strict.`;
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
      instructions: `You are a revision verification reviewer. Decide only whether the candidate truly fixes the defect without introducing a new one.
Check the story bible, episode contract, previous exit state, scene action, adversarial dialogue, shootable hook, and prop state.
Fail only for a material issue affecting comprehension, retention, or production.`,
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
        instructions: `You are the delivery revision writer. Repair only material defects in the issue ledger while preserving the episode contract, source facts, approved names, and dynamic scene count.
Return complete scenes without explaining the revision process. Never evade an issue through added narration, repeated dialogue, invented rules, or removal of a key fact.
The repaired episode must still meet runtime, dialogue-density, speaking-character, and action-rhythm budgets.`,
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
