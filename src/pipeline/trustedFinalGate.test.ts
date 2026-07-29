import { describe, expect, it } from "vitest";
import type {
  AdaptationOptions,
  CharacterProfile,
  Episode,
  ScriptScene,
  StoryBible,
} from "../domain";
import { estimateEpisodeRuntime } from "./episodeBudget";
import { renderEpisode } from "./offline";
import { runTrustedFinalGate } from "./trustedFinalGate";

const options: AdaptationOptions = {
  episodeCount: 1,
  durationSeconds: 60,
  scenesPerEpisode: 3,
  genre: "古装悬疑",
  tone: "紧张",
  trendPreset: "精品爽剧",
};

const characters: CharacterProfile[] = [
  {
    id: "character-1",
    sourceName: "程青",
    targetName: "程野",
    role: "核心主角",
    traits: ["机敏"],
    occurrences: 12,
    locked: true,
    nameSource: "manual",
  },
];

const storyBible: StoryBible = {
  premise: "程野归宗后以旧印追查内鬼。",
  canonicalCharacters: [
    {
      id: "character-1",
      sourceNames: ["程青"],
      scriptName: "程野",
      role: "核心主角",
      relationships: ["与顾川互相怀疑"],
      evidenceChapterIds: ["chapter-1"],
    },
  ],
  worldRules: [
    {
      id: "rule-1",
      subject: "宗门旧印",
      fact: "旧印被人调换",
      cause: "内鬼阻止程野自证",
      evidenceChapterIds: ["chapter-1"],
    },
  ],
  propThreads: [],
  timeline: [
    {
      id: "event-1",
      order: 1,
      location: "山门",
      time: "日",
      participants: ["程野", "顾川"],
      cause: "程野归宗",
      event: "程野当众验印",
      effect: "顾川成为嫌疑人",
      evidenceChapterIds: ["chapter-1"],
    },
  ],
};

function richScenes(): ScriptScene[] {
  const dialogue = [
    { speaker: "程野", text: "我若是假冒者，怎敢当众验旧印？" },
    { speaker: "顾川", text: "旧印百年前就丢了，你拿什么验？" },
    { speaker: "程野", text: "拿你袖里的朱砂，验它沾的是谁的血。" },
    { speaker: "顾川", text: "一撮朱砂而已，凭什么指认我？" },
  ];
  return [0, 1, 2].map((index) => ({
    id: `episode-1-scene-${index + 1}`,
    heading: index ? "内景 议事堂 - 日" : "外景 山门 - 日",
    location: index ? "议事堂" : "山门",
    action:
      "剑锋贴住程野喉结。程野压下剑尖，把破损信物按上验印石。石面骤亮，顾川袖口落下一撮带血朱砂。",
    dialogue,
  }));
}

function episode(): Episode {
  const scenes = richScenes();
  const item: Episode = {
    id: "episode-1",
    number: 1,
    title: "袖中朱砂",
    sourceChapterIds: ["chapter-1"],
    plannedSceneCount: 3,
    openingHook: "剑锋抵住程野喉结",
    objective: "程野当众证明身份",
    reversal: "顾川袖中落下带血朱砂",
    endHook: "山门落锁，顾川成为嫌疑人",
    contract: {
      dominantConflict: "程野以验印反制顾川的冒名指控",
      newInformation: ["顾川袖中藏有带血朱砂"],
      visualHook: "剑锋抵住程野喉结",
      transitionFromPrevious: "首集从山门开始",
      activePropThreads: [],
      entryState: "程野被拦在山门外",
      exitState: "顾川成为旧印案嫌疑人",
    },
    runtime: estimateEpisodeRuntime(scenes),
    semanticAudit: { passed: true, score: 90, issues: [] },
    scenes,
    content: "",
  };
  item.content = renderEpisode(item, 60);
  return item;
}

describe("成稿尾段可信闭环", () => {
  it("跨集审片登记问题，定向修复后复验并保留完整台账", async () => {
    const calls: Array<{ name: string; route?: string }> = [];
    const result = await runTrustedFinalGate({
      episodes: [episode()],
      characters,
      options,
      storyBible,
      callStructured: async <T,>(payload: {
        name: string;
        route?: "primary" | "flash";
      }): Promise<T> => {
        calls.push({ name: payload.name, route: payload.route });
        if (payload.name === "series_quality_audit_window-1-1") {
          return {
            passed: false,
            score: 72,
            issues: [
              {
                id: "hook-not-in-scene",
                severity: "major",
                category: "hook",
                episodeNumbers: [1],
                evidence: "结尾卡点没有形成正在发生的动作",
                repairInstruction: "让落锁动作直接打断对峙并卡黑",
              },
            ],
          } as T;
        }
        if (payload.name === "episode_1_final_repair") {
          return {
            scenes: richScenes().map(({ id: _id, ...scene }) => scene),
          } as T;
        }
        if (payload.name === "episode_1_final_semantic_audit") {
          return {
            passed: true,
            score: 96,
            issues: [],
            repairBrief: [],
          } as T;
        }
        if (payload.name === "series_quality_verify_window-1-1") {
          return {
            passed: true,
            score: 95,
            issues: [],
          } as T;
        }
        throw new Error(`Unexpected call: ${payload.name}`);
      },
    });

    expect(result.quality.gate?.status).toBe("passed");
    expect(result.quality.gate?.repairAttempts).toBe(1);
    expect(result.quality.gate?.acceptedRepairs).toBe(1);
    expect(result.quality.gate?.issues[0].status).toBe("resolved");
    expect(
      calls.find((call) => call.name.includes("quality_audit"))?.route,
    ).toBe("flash");
    expect(
      calls.find((call) => call.name.endsWith("_final_repair"))?.route,
    ).toBe("primary");
  });
});
