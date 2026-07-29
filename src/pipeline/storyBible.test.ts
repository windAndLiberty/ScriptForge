import { describe, expect, it } from "vitest";
import type {
  CharacterProfile,
  EpisodeContract,
  StoryBible,
} from "../domain";
import {
  validateEpisodeContracts,
  validateStoryBible,
} from "./storyBible";
import {
  assessEpisodeScenes,
  estimateEpisodeRuntime,
} from "./episodeBudget";

const characters: CharacterProfile[] = [
  {
    id: "character-1",
    sourceName: "陈青云",
    targetName: "陈砚",
    role: "核心主角",
    traits: [],
    occurrences: 10,
    locked: true,
    nameSource: "manual",
  },
];

const bible: StoryBible = {
  premise: "陈砚从天渊归来，追查百年前被暗算的真相。",
  canonicalCharacters: [
    {
      id: "character-1",
      sourceNames: ["陈青云"],
      scriptName: "陈砚",
      role: "核心主角",
      relationships: [],
      evidenceChapterIds: ["chapter-1"],
    },
  ],
  worldRules: [
    {
      id: "rule-1",
      subject: "陈砚的灵脉",
      fact: "表面被天渊侵蚀，暂时无法运转",
      cause: "灵脉中残留林道远的独门剑气",
      evidenceChapterIds: ["chapter-1"],
    },
  ],
  propThreads: [
    {
      id: "prop-soul-lamp",
      name: "魂灯",
      dramaticFunction: "保存残魂并修复灵脉",
      introducedEpisode: 1,
      payoffEpisode: 3,
      currentState: "熄灭百年后重燃",
      evidenceChapterIds: ["chapter-1"],
    },
  ],
  timeline: [
    {
      id: "event-1",
      order: 1,
      location: "天渊",
      time: "百年后",
      participants: ["陈砚"],
      cause: "封印松动",
      event: "陈砚走出天渊",
      effect: "宗门魂灯重燃",
      evidenceChapterIds: ["chapter-1"],
    },
  ],
};

function contract(
  dominantConflict: string,
  transitionFromPrevious: string,
): EpisodeContract {
  return {
    dominantConflict,
    newInformation: ["魂灯能够保存残魂"],
    visualHook: "熄灭百年的魂灯骤然燃烧",
    transitionFromPrevious,
    activePropThreads: ["prop-soul-lamp"],
    entryState: "陈砚被宗门怀疑",
    exitState: "陈砚发现林道远剑气",
  };
}

describe("Huobao 对齐后的故事圣经与连续性门禁", () => {
  it("允许同一人物在一个稳定ID下维护多个原著别名", () => {
    const aliased = structuredClone(bible);
    aliased.canonicalCharacters.push({
      id: "character-2",
      sourceNames: ["东雪瑶", "白惜雪"],
      scriptName: "沈知雪",
      role: "关键配角",
      relationships: ["陈砚的前未婚妻"],
      evidenceChapterIds: ["chapter-2", "chapter-3"],
    });
    expect(validateStoryBible(aliased, characters).passed).toBe(true);
  });

  it("阻断相邻分集重复同一个退婚冲突", () => {
    const result = validateEpisodeContracts(
      [
        contract("东雪瑶当众退婚并羞辱陈砚", "首集"),
        contract("白惜雪再次解释退婚条件", "次日转入偏殿"),
      ],
      bible,
    );
    expect(result.passed).toBe(false);
    expect(result.issues.join("")).toContain("核心冲突重复");
  });

  it("60秒以对白、停顿、动作和转场共同估时", () => {
    const scenes = [0, 1].map((sceneIndex) => ({
      heading: sceneIndex ? "内景 宗门偏殿 - 日" : "外景 山门 - 日",
      location: sceneIndex ? "宗门偏殿" : "山门",
      action:
        "魂灯突然燃起。陈砚抬手挡剑，反将婚书压在灯下。火焰转黑，众人同时后退。",
      dialogue: Array.from({ length: 6 }, (_, lineIndex) => ({
        speaker: lineIndex % 2 ? "沈知雪" : "陈砚",
        text:
          lineIndex % 2
            ? "一个废人，也配拒绝这门婚事？"
            : "婚可以退，这盏魂灯必须留下。",
      })),
    }));
    const runtime = estimateEpisodeRuntime(scenes);
    const assessment = assessEpisodeScenes(scenes, {
      durationSeconds: 60,
      scenesPerEpisode: 2,
    });
    expect(runtime.estimatedSeconds).toBeGreaterThanOrEqual(49);
    expect(runtime.estimatedSeconds).toBeLessThanOrEqual(69);
    expect(assessment.issues.join("")).not.toContain("预计仅");
  });
});
