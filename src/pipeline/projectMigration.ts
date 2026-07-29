import type {
  AdaptationOptions,
  AdaptationResult,
  CharacterProfile,
  DialogueLine,
  Episode,
  EpisodeContract,
  NovelDocument,
  QualityGateIssue,
  QualityGateTraceStep,
  QualityIssueSeverity,
  ScriptScene,
  StoryBible,
} from "../domain";
import { evaluateScript } from "./quality";
import { estimateEpisodeRuntime } from "./episodeBudget";
import {
  isGenericCharacterName,
  isPlausibleSourceCharacterName,
} from "./characters";

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function text(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function number(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function stringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

export function sanitizeDocument(value: unknown): NovelDocument | null {
  const source = record(value);
  if (!source) return null;
  const rawText = text(source.rawText);
  const chapters = Array.isArray(source.chapters)
    ? source.chapters.flatMap((item, position) => {
        const chapter = record(item);
        if (!chapter) return [];
        const content = text(chapter.content);
        return [
          {
            id: text(chapter.id, `chapter-${position + 1}`),
            index: number(chapter.index, position + 1),
            title: text(chapter.title, `第${position + 1}章`),
            content,
            charCount: number(
              chapter.charCount,
              content.replace(/\s/g, "").length,
            ),
          },
        ];
      })
    : [];
  if (!rawText && !chapters.length) return null;
  return {
    fileName: text(source.fileName, "novel.txt"),
    title: text(source.title, "未命名小说"),
    author: text(source.author, "未知作者"),
    intro: text(source.intro),
    rawText: rawText || chapters.map((chapter) => chapter.content).join("\n"),
    charCount: number(
      source.charCount,
      (rawText || chapters.map((chapter) => chapter.content).join(""))
        .replace(/\s/g, "")
        .length,
    ),
    chapters,
  };
}

export function sanitizeCharacters(value: unknown): CharacterProfile[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item, position) => {
    const character = record(item);
    if (!character) return [];
    const sourceName = text(character.sourceName);
    const targetName = text(character.targetName);
    if (!sourceName && !targetName) return [];
    if (sourceName && !isPlausibleSourceCharacterName(sourceName)) return [];
    const hasPlaceholderName = isGenericCharacterName(targetName);
    return [
      {
        id: text(character.id, `character-${position + 1}`),
        sourceName: sourceName || targetName,
        targetName: hasPlaceholderName ? "" : targetName || sourceName,
        role: text(character.role, "主要角色"),
        traits: stringArray(character.traits),
        occurrences: number(character.occurrences, 0),
        locked: hasPlaceholderName ? false : character.locked !== false,
        nameSource:
          character.nameSource === "model" ||
          character.nameSource === "manual"
            ? character.nameSource
            : "local",
      },
    ];
  });
}

function sanitizeDialogue(value: unknown): DialogueLine[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const line = record(item);
    if (!line) return [];
    const speaker = text(line.speaker, "角色");
    const content = text(line.text);
    if (!content) return [];
    return [{ speaker, text: content }];
  });
}

function sanitizeScenes(value: unknown, episodeNumber: number): ScriptScene[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item, position) => {
    const scene = record(item);
    if (!scene) return [];
    return [
      {
        id: text(
          scene.id,
          `episode-${episodeNumber}-scene-${position + 1}`,
        ),
        heading: text(scene.heading, "内景 日"),
        location: text(scene.location, "未标注场景"),
        action: text(scene.action),
        dialogue: sanitizeDialogue(scene.dialogue),
      },
    ];
  });
}

function sanitizeEpisodeContract(value: unknown): EpisodeContract | undefined {
  const source = record(value);
  if (!source) return undefined;
  return {
    dominantConflict: text(source.dominantConflict),
    newInformation: stringArray(source.newInformation),
    visualHook: text(source.visualHook),
    transitionFromPrevious: text(source.transitionFromPrevious),
    activePropThreads: stringArray(source.activePropThreads),
    entryState: text(source.entryState),
    exitState: text(source.exitState),
  };
}

function sanitizeSemanticAudit(
  value: unknown,
): import("../domain").EpisodeSemanticAudit | undefined {
  const source = record(value);
  if (!source) return undefined;
  return {
    score: number(source.score, 0),
    passed: source.passed === true,
    issues: stringArray(source.issues),
  };
}

function sanitizeQualityGate(
  value: unknown,
): import("../domain").QualityGateReport | undefined {
  const source = record(value);
  if (!source || source.version !== "trusted-quality-gate-v1") {
    return undefined;
  }
  const issues: QualityGateIssue[] = Array.isArray(source.issues)
    ? source.issues.flatMap<QualityGateIssue>((item, index) => {
        const issue = record(item);
        if (!issue) return [];
        const severity: QualityIssueSeverity =
          issue.severity === "blocker" ||
          issue.severity === "major" ||
          issue.severity === "minor"
            ? issue.severity
            : "major";
        const categories = [
          "source_fidelity",
          "continuity",
          "character",
          "pacing",
          "hook",
          "dialogue",
          "production",
          "compliance",
        ] as const;
        const category = categories.includes(
          issue.category as (typeof categories)[number],
        )
          ? (issue.category as (typeof categories)[number])
          : "continuity";
        return [
          {
            id: text(issue.id, `gate-issue-${index + 1}`),
            severity,
            category,
            episodeNumbers: Array.isArray(issue.episodeNumbers)
              ? issue.episodeNumbers.filter(
                  (episode): episode is number =>
                    typeof episode === "number" &&
                    Number.isInteger(episode) &&
                    episode > 0,
                )
              : [],
            evidence: text(issue.evidence),
            repairInstruction: text(issue.repairInstruction),
            status: issue.status === "resolved" ? "resolved" : "open",
          },
        ];
      })
    : [];
  const trace: QualityGateTraceStep[] = Array.isArray(source.trace)
    ? source.trace.flatMap<QualityGateTraceStep>((item, index) => {
        const step = record(item);
        if (!step) return [];
        const stages = [
          "deterministic_precheck",
          "window_audit",
          "targeted_repair",
          "verification",
          "delivery_gate",
        ] as const;
        const statuses = [
          "passed",
          "failed",
          "accepted",
          "rejected",
        ] as const;
        return [
          {
            id: text(step.id, `gate-step-${index + 1}`),
            stage: stages.includes(
              step.stage as (typeof stages)[number],
            )
              ? (step.stage as (typeof stages)[number])
              : "verification",
            status: statuses.includes(
              step.status as (typeof statuses)[number],
            )
              ? (step.status as (typeof statuses)[number])
              : "failed",
            episodeNumbers: Array.isArray(step.episodeNumbers)
              ? step.episodeNumbers.filter(
                  (episode): episode is number =>
                    typeof episode === "number" &&
                    Number.isInteger(episode) &&
                    episode > 0,
                )
              : [],
            detail: text(step.detail),
          },
        ];
      })
    : [];
  return {
    version: "trusted-quality-gate-v1",
    status: source.status === "passed" ? "passed" : "needs_review",
    deterministicScore: number(source.deterministicScore, 0),
    auditedWindows: number(source.auditedWindows, 0),
    repairAttempts: number(source.repairAttempts, 0),
    acceptedRepairs: number(source.acceptedRepairs, 0),
    openIssueCount: number(
      source.openIssueCount,
      issues.filter((issue) => issue.status === "open").length,
    ),
    issues,
    trace,
  };
}

function sanitizeStoryBible(value: unknown): StoryBible | undefined {
  const source = record(value);
  if (!source) return undefined;
  const canonicalCharacters = Array.isArray(source.canonicalCharacters)
    ? source.canonicalCharacters.flatMap((item, index) => {
        const character = record(item);
        if (!character) return [];
        return [{
          id: text(character.id, `character-${index + 1}`),
          sourceNames: stringArray(character.sourceNames),
          scriptName: text(character.scriptName),
          role: text(character.role),
          relationships: stringArray(character.relationships),
          evidenceChapterIds: stringArray(character.evidenceChapterIds),
        }];
      })
    : [];
  const worldRules = Array.isArray(source.worldRules)
    ? source.worldRules.flatMap((item, index) => {
        const rule = record(item);
        if (!rule) return [];
        return [{
          id: text(rule.id, `rule-${index + 1}`),
          subject: text(rule.subject),
          fact: text(rule.fact),
          cause: text(rule.cause),
          evidenceChapterIds: stringArray(rule.evidenceChapterIds),
        }];
      })
    : [];
  const propThreads = Array.isArray(source.propThreads)
    ? source.propThreads.flatMap((item, index) => {
        const prop = record(item);
        if (!prop) return [];
        return [{
          id: text(prop.id, `prop-${index + 1}`),
          name: text(prop.name),
          dramaticFunction: text(prop.dramaticFunction),
          introducedEpisode: number(prop.introducedEpisode, 1),
          payoffEpisode: number(prop.payoffEpisode, 1),
          currentState: text(prop.currentState),
          evidenceChapterIds: stringArray(prop.evidenceChapterIds),
        }];
      })
    : [];
  const timeline = Array.isArray(source.timeline)
    ? source.timeline.flatMap((item, index) => {
        const event = record(item);
        if (!event) return [];
        return [{
          id: text(event.id, `event-${index + 1}`),
          order: number(event.order, index + 1),
          location: text(event.location),
          time: text(event.time),
          participants: stringArray(event.participants),
          cause: text(event.cause),
          event: text(event.event),
          effect: text(event.effect),
          evidenceChapterIds: stringArray(event.evidenceChapterIds),
        }];
      })
    : [];
  return {
    premise: text(source.premise),
    canonicalCharacters,
    worldRules,
    propThreads,
    timeline,
  };
}

function sanitizeEpisodes(value: unknown): Episode[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item, position) => {
    const episode = record(item);
    if (!episode) return [];
    const episodeNumber = number(episode.number, position + 1);
    const scenes = sanitizeScenes(episode.scenes, episodeNumber);
    const content =
      text(episode.content) ||
      [
        `第${episodeNumber}集《${text(episode.title, `第${episodeNumber}集`)}》`,
        "",
        ...scenes.flatMap((scene, sceneIndex) => [
          `${sceneIndex + 1}. ${scene.heading} ${scene.location}`,
          `△ ${scene.action}`,
          ...scene.dialogue.map((line) => `${line.speaker}：${line.text}`),
          "",
        ]),
      ].join("\n");
    return [
      {
        id: text(episode.id, `episode-${episodeNumber}`),
        number: episodeNumber,
        title: text(episode.title, `第${episodeNumber}集`),
        sourceChapterIds: stringArray(episode.sourceChapterIds),
        plannedSceneCount: number(
          episode.plannedSceneCount,
          scenes.length,
        ),
        openingHook: text(episode.openingHook),
        objective: text(episode.objective),
        reversal: text(episode.reversal),
        endHook: text(episode.endHook),
        contract: sanitizeEpisodeContract(episode.contract),
        runtime: estimateEpisodeRuntime(scenes),
        semanticAudit: sanitizeSemanticAudit(episode.semanticAudit),
        scenes,
        content,
      },
    ];
  });
}

export function sanitizeAdaptationResult(
  value: unknown,
  options: AdaptationOptions,
  characters: CharacterProfile[],
): AdaptationResult | null {
  const source = record(value);
  if (!source) return null;
  const episodes = sanitizeEpisodes(source.episodes);
  if (!episodes.length) return null;
  const storyBible = sanitizeStoryBible(source.storyBible);
  const result: AdaptationResult = {
    logline: text(source.logline),
    genre: text(source.genre, options.genre),
    themes: stringArray(source.themes),
    sourceFacts: stringArray(source.sourceFacts),
    storyBible,
    episodes,
    quality: {
      score: 0,
      metrics: [],
      warnings: [],
      passed: false,
    },
    generatedAt: text(source.generatedAt, new Date().toISOString()),
    mode: source.mode === "online" ? "online" : "offline",
  };
  result.quality = evaluateScript(
    episodes,
    characters,
    options,
    storyBible,
  );
  const savedQuality = record(source.quality);
  const gate = sanitizeQualityGate(savedQuality?.gate);
  if (gate) {
    result.quality.gate = gate;
    result.quality.passed =
      result.quality.passed && gate.status === "passed";
  }
  return result;
}
