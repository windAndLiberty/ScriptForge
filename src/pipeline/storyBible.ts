import type {
  CharacterProfile,
  EpisodeContract,
  PropThread,
  StoryBible,
  TimelineEvent,
  WorldRule,
} from "../domain";

export interface BibleValidation {
  passed: boolean;
  issues: string[];
}

function normalizedTerms(value: string) {
  return new Set(
    value
      .replace(/[，。！？、；：“”‘’（）【】\s]/g, "")
      .split(/(?:与|和|被|因|由|是|为|在|的|了|将|对|向)/)
      .filter((item) => item.length >= 2),
  );
}

function overlapRatio(left: string, right: string) {
  const a = normalizedTerms(left);
  const b = normalizedTerms(right);
  if (!a.size || !b.size) return 0;
  const overlap = [...a].filter((item) => b.has(item)).length;
  return overlap / Math.min(a.size, b.size);
}

const conflictKeywords = [
  "退婚",
  "羞辱",
  "逐出",
  "自证",
  "追杀",
  "调查",
  "觉醒",
  "复仇",
  "争夺",
  "救人",
  "揭露",
  "对决",
  "逃亡",
  "夺权",
  "认亲",
  "逼婚",
  "背叛",
];

function repeatsDominantConflict(left: string, right: string) {
  if (overlapRatio(left, right) >= 0.7) return true;
  const leftKeywords = conflictKeywords.filter((keyword) =>
    left.includes(keyword),
  );
  const rightKeywords = new Set(
    conflictKeywords.filter((keyword) => right.includes(keyword)),
  );
  return leftKeywords.some((keyword) => rightKeywords.has(keyword));
}

export function emptyStoryBible(
  characters: CharacterProfile[] = [],
): StoryBible {
  return {
    premise: "",
    canonicalCharacters: characters.map((character) => ({
      id: character.id,
      sourceNames: [character.sourceName],
      scriptName: character.targetName,
      role: character.role,
      relationships: [],
      evidenceChapterIds: [],
    })),
    worldRules: [],
    propThreads: [],
    timeline: [],
  };
}

export function validateStoryBible(
  bible: StoryBible,
  characters: CharacterProfile[],
): BibleValidation {
  const issues: string[] = [];
  if (!bible || typeof bible !== "object") {
    return { passed: false, issues: ["模型未返回有效故事圣经"] };
  }
  const canonicalCharacters = Array.isArray(bible.canonicalCharacters)
    ? bible.canonicalCharacters
    : [];
  const worldRules = Array.isArray(bible.worldRules) ? bible.worldRules : [];
  const timeline = Array.isArray(bible.timeline) ? bible.timeline : [];
  const canonicalNames = new Set(
    canonicalCharacters.map((character) =>
      String(character.scriptName || "").trim(),
    ),
  );
  const expectedNames = characters.map((character) => character.targetName.trim());
  expectedNames.forEach((name) => {
    if (name && !canonicalNames.has(name)) {
      issues.push(`故事圣经缺少已确认角色“${name}”`);
    }
  });

  const aliases = new Map<string, string>();
  canonicalCharacters.forEach((character) => {
    [...(Array.isArray(character.sourceNames) ? character.sourceNames : []), character.scriptName]
      .map((name) => String(name || "").trim())
      .filter(Boolean)
      .forEach((name) => {
        const owner = aliases.get(name);
        if (owner && owner !== character.id) {
          issues.push(`人物别名“${name}”同时归属于多个角色`);
        } else {
          aliases.set(name, character.id);
        }
      });
  });

  worldRules.forEach((rule, index) => {
    worldRules.slice(index + 1).forEach((candidate) => {
      if (
        rule.subject.trim() === candidate.subject.trim() &&
        overlapRatio(`${rule.fact}${rule.cause}`, `${candidate.fact}${candidate.cause}`) >=
          0.75 &&
        rule.fact.trim() !== candidate.fact.trim()
      ) {
        issues.push(
          `世界规则可能冲突：“${rule.subject}—${rule.fact}”与“${candidate.fact}”`,
        );
      }
    });
  });

  const eventOrders = timeline.map((event) => event.order);
  if (new Set(eventOrders).size !== eventOrders.length) {
    issues.push("时间线存在重复顺序号");
  }
  timeline.forEach((event) => {
    if (!event.location.trim()) issues.push(`时间线事件“${event.event}”缺少地点`);
    if (!event.cause.trim() || !event.effect.trim()) {
      issues.push(`时间线事件“${event.event}”缺少因果`);
    }
  });

  return { passed: issues.length === 0, issues };
}

export function validateEpisodeContracts(
  contracts: EpisodeContract[],
  bible: StoryBible,
): BibleValidation {
  const issues: string[] = [];
  contracts.forEach((contract, index) => {
    const episode = index + 1;
    if (!contract.dominantConflict.trim()) {
      issues.push(`第${episode}集缺少唯一核心冲突`);
    }
    if (!contract.newInformation.length) {
      issues.push(`第${episode}集没有新增信息`);
    }
    if (!contract.visualHook.trim()) {
      issues.push(`第${episode}集缺少可视化前5秒钩子`);
    }
    if (episode > 1 && !contract.transitionFromPrevious.trim()) {
      issues.push(`第${episode}集缺少与上一集的转场因果`);
    }
    const previous = contracts[index - 1];
    if (
      previous &&
      repeatsDominantConflict(
        previous.dominantConflict,
        contract.dominantConflict,
      )
    ) {
      issues.push(
        `第${episode - 1}、${episode}集核心冲突重复：${contract.dominantConflict}`,
      );
    }
    if (
      previous &&
      previous.exitState.trim() &&
      contract.entryState.trim() &&
      overlapRatio(previous.exitState, contract.entryState) < 0.15 &&
      !contract.transitionFromPrevious.trim()
    ) {
      issues.push(`第${episode}集入场状态没有承接上一集`);
    }
  });

  const referencedProps = new Set(
    contracts.flatMap((contract) => contract.activePropThreads),
  );
  const propThreads = Array.isArray(bible.propThreads)
    ? bible.propThreads
    : [];
  propThreads.forEach((prop) => {
    if (!referencedProps.has(prop.id) && !referencedProps.has(prop.name)) {
      issues.push(`道具线“${prop.name}”已建立但没有进入任何分集`);
    }
    if (prop.payoffEpisode < prop.introducedEpisode) {
      issues.push(`道具线“${prop.name}”的兑现集早于引入集`);
    }
  });

  return { passed: issues.length === 0, issues };
}

export function compactStoryBible(bible: StoryBible) {
  return {
    premise: bible.premise,
    characters: bible.canonicalCharacters.map((character) => ({
      id: character.id,
      aliases: character.sourceNames,
      name: character.scriptName,
      role: character.role,
      relationships: character.relationships,
    })),
    rules: bible.worldRules.map((rule) => ({
      subject: rule.subject,
      fact: rule.fact,
      cause: rule.cause,
    })),
    props: bible.propThreads.map((prop) => ({
      id: prop.id,
      name: prop.name,
      function: prop.dramaticFunction,
      introducedEpisode: prop.introducedEpisode,
      payoffEpisode: prop.payoffEpisode,
      state: prop.currentState,
    })),
    timeline: bible.timeline.map((event) => ({
      order: event.order,
      location: event.location,
      time: event.time,
      participants: event.participants,
      cause: event.cause,
      event: event.event,
      effect: event.effect,
    })),
  };
}

export function sanitizeWorldRule(value: WorldRule, index: number): WorldRule {
  return {
    id: value.id || `rule-${index + 1}`,
    subject: value.subject || "",
    fact: value.fact || "",
    cause: value.cause || "",
    evidenceChapterIds: Array.isArray(value.evidenceChapterIds)
      ? value.evidenceChapterIds
      : [],
  };
}

export function sanitizePropThread(value: PropThread, index: number): PropThread {
  return {
    id: value.id || `prop-${index + 1}`,
    name: value.name || "",
    dramaticFunction: value.dramaticFunction || "",
    introducedEpisode: Number(value.introducedEpisode) || 1,
    payoffEpisode:
      Number(value.payoffEpisode) || Number(value.introducedEpisode) || 1,
    currentState: value.currentState || "",
    evidenceChapterIds: Array.isArray(value.evidenceChapterIds)
      ? value.evidenceChapterIds
      : [],
  };
}

export function sanitizeTimelineEvent(
  value: TimelineEvent,
  index: number,
): TimelineEvent {
  return {
    id: value.id || `event-${index + 1}`,
    order: Number(value.order) || index + 1,
    location: value.location || "",
    time: value.time || "",
    participants: Array.isArray(value.participants) ? value.participants : [],
    cause: value.cause || "",
    event: value.event || "",
    effect: value.effect || "",
    evidenceChapterIds: Array.isArray(value.evidenceChapterIds)
      ? value.evidenceChapterIds
      : [],
  };
}
