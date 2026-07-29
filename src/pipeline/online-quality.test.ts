import { describe, expect, it } from "vitest";
import type {
  AdaptationOptions,
  CharacterProfile,
  NovelDocument,
} from "../domain";
import {
  generateModelCharacterNames,
  runOnlinePipeline,
} from "./online";

const document: NovelDocument = {
  fileName: "test.txt",
  title: "测试故事",
  author: "测试者",
  intro: "",
  rawText: "程青从裂缝归来，宗门众人怀疑他的身份。",
  charCount: 2_200,
  chapters: [
    {
      id: "chapter-1",
      index: 1,
      title: "归宗",
      content:
        "程青从裂缝归来，发现信物被人调换。他没有急着解释，而是当众要求查验宗门旧印。",
      charCount: 48,
    },
  ],
};

const characters: CharacterProfile[] = [
  {
    id: "character-1",
    sourceName: "程青",
    targetName: "程野",
    role: "核心主角",
    traits: ["克制", "机敏"],
    occurrences: 20,
    locked: false,
  },
];

const options: AdaptationOptions = {
  episodeCount: 1,
  durationSeconds: 60,
  scenesPerEpisode: 3,
  genre: "古装逆袭",
  tone: "悬疑、高燃",
  trendPreset: "精品爽剧",
};

const richDialogue = [
  {
    speaker: "程野",
    text: "我若是假冒者，怎敢当众验旧印？",
  },
  { speaker: "顾川", text: "旧印百年前就失踪了，你拿什么验？" },
  { speaker: "程野", text: "拿你袖里的朱砂，验它沾的是谁的血。" },
  { speaker: "顾川", text: "一撮朱砂而已，凭什么指认我？" },
];

describe("在线成稿质量修订", () => {
  it("用户手动修改并锁定的姓名不会再次调用 Flash 或被覆盖", async () => {
    let called = false;
    const manuallyNamed = [
      { ...characters[0], locked: true, nameSource: "manual" as const },
    ];
    const result = await generateModelCharacterNames({
      document,
      characters: manuallyNamed,
      options,
      callStructured: async <T,>(): Promise<T> => {
        called = true;
        throw new Error("不应调用");
      },
    });

    expect(called).toBe(false);
    expect(result[0].targetName).toBe("程野");
  });

  it("初稿过薄时会自动重写，并输出纯剧本而非重复提纲标签", async () => {
    const calls: string[] = [];
    const result = await runOnlinePipeline({
      document,
      characters,
      options,
      callStructured: async <T,>(payload: {
        name: string;
        schema?: Record<string, unknown>;
        route?: "primary" | "flash";
      }): Promise<T> => {
        calls.push(payload.name);
        if (payload.name === "character_naming") {
          expect(payload.route).toBe("flash");
          return {
            renames: [{ sourceName: "程青", targetName: "程野" }],
          } as T;
        }
        if (payload.name === "chapter_analysis") {
          expect(payload.route).toBe("flash");
          return {
            summary: "程野归宗并以旧印自证。",
            facts: ["程野从裂缝归来", "宗门旧印被调换"],
            keyEvents: ["归宗", "验印"],
            emotionalBeats: ["怀疑", "反制"],
            productionNotes: ["集中在山门与议事堂"],
          } as T;
        }
        if (payload.name.endsWith("_semantic_audit")) {
          expect(payload.route).toBe("flash");
          return {
            passed: true,
            score: 94,
            issues: [],
            repairBrief: [],
          } as T;
        }
        if (payload.name.startsWith("series_quality_")) {
          expect(payload.route).toBe("flash");
          return {
            passed: true,
            score: 96,
            issues: [],
          } as T;
        }
        if (payload.name === "story_bible") {
          expect(payload.route).toBe("primary");
          return {
            premise: "程野归宗后追查旧印被调换的真相。",
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
                fact: "旧印已被调换",
                cause: "有人试图阻止程野自证",
                evidenceChapterIds: ["chapter-1"],
              },
            ],
            propThreads: [],
            timeline: [
              {
                id: "event-1",
                order: 1,
                location: "玄青宗山门",
                time: "日",
                participants: ["程野", "顾川"],
                cause: "程野归宗",
                event: "程野要求验印",
                effect: "顾川袖中印泥暴露",
                evidenceChapterIds: ["chapter-1"],
              },
            ],
          } as T;
        }
        if (payload.name === "episode_outline") {
          expect(payload.route).toBe("primary");
          return {
            logline: "程野以一枚被调换的旧印反制冒名指控。",
            genre: "古装悬疑逆袭",
            themes: ["身份", "信任"],
            sourceFacts: ["宗门旧印被调换"],
            episodes: [
              {
                number: 1,
                title: "袖中印泥",
                sourceChapterIds: ["chapter-1"],
                sceneCount: 3,
                openingHook: "程野刚踏进山门，就被剑锋抵住喉咙。",
                objective: "程野必须在众人面前证明身份。",
                reversal: "真正动过旧印的人露出带血印泥。",
                endHook: "印泥指向最信任的师兄。",
                dominantConflict: "程野以验印反制顾川的冒名指控",
                newInformation: ["顾川袖中藏有带血印泥"],
                visualHook: "剑锋抵住程野喉咙",
                transitionFromPrevious: "首集从程野抵达山门开始",
                activePropThreads: [],
                entryState: "程野被当成冒名者拦在山门外",
                exitState: "顾川成为调换旧印的嫌疑人",
              },
            ],
          } as T;
        }
        if (payload.name === "episode_1") {
          const sceneItem = (
            payload.schema as {
              properties: {
                scenes: {
                  items: {
                    properties: {
                      action: { minLength: number };
                      dialogue: {
                        minItems: number;
                        items: {
                          properties: {
                            text: { minLength: number; maxLength?: number };
                          };
                        };
                      };
                    };
                  };
                };
              };
            }
          ).properties.scenes.items;
          expect(sceneItem.properties.action.minLength).toBe(1);
          expect(
            sceneItem.properties.dialogue.items.properties.text.minLength,
          ).toBe(1);
          expect(
            sceneItem.properties.dialogue.items.properties.text.maxLength,
          ).toBeUndefined();
          expect(
            (
              payload.schema as {
                properties: {
                  scenes: {
                    minItems: number;
                    items: {
                      properties: {
                        dialogue: { minItems: number };
                      };
                    };
                  };
                };
              }
            ).properties.scenes.minItems,
          ).toBe(1);
          expect(sceneItem.properties.dialogue.minItems).toBe(1);
          return {
            scenes: [
              {
                heading: "外景 山门 - 日",
                location: "山门",
                action: "程野走进山门。",
                dialogue: [
                  { speaker: "程野", text: "我回来了。" },
                  { speaker: "顾川", text: "你是谁？" },
                ],
              },
            ],
          } as T;
        }
        if (payload.name === "episode_1_rewrite") {
          return {
            scenes: [
              {
                heading: "外景 山门 - 日",
                location: "山门",
                action: "程野仍然只是站在山门前，没有形成新的动作变化。",
                dialogue: [
                  { speaker: "程野", text: "我会证明身份。" },
                  { speaker: "顾川", text: "那就证明给我看。" },
                ],
              },
            ],
          } as T;
        }
        return {
          scenes: [0, 1, 2].map((index) => ({
            heading: index === 0 ? "外景 山门 - 日" : "内景 议事堂 - 日",
            location: index === 0 ? "玄青宗山门" : "玄青宗议事堂",
            action:
              "剑锋贴住程野喉结。程野压下剑尖，把破损信物按上验印石。石面骤亮，顾川袖口落下一撮带血朱砂。众人转头盯住顾川，山门轰然落锁。",
            dialogue: richDialogue.map((line, lineIndex) => ({
              ...line,
              text:
                index === 2 && lineIndex === 3
                  ? "门外还有一个人！"
                  : line.text,
            })),
          })),
        } as T;
      },
    });

    expect(calls[0]).toBe("character_naming");
    expect(calls).toContain("episode_1_rewrite");
    expect(calls).toContain("episode_1_rewrite_2");
    expect(result.episodes[0].plannedSceneCount).toBe(3);
    expect(result.episodes[0].scenes).toHaveLength(3);
    expect(result.episodes[0].content).not.toContain("【冷开场】");
    expect(
      result.quality.metrics.find((metric) => metric.id === "completeness")
        ?.score,
    ).toBeGreaterThanOrEqual(85);
    expect(result.quality.gate?.status).toBe("passed");
    expect(calls).toContain("series_quality_audit_window-1-1");
  });
});
