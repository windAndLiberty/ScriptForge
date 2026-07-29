import { describe, expect, it } from "vitest";
import type { AdaptationOptions } from "../domain";
import {
  applyRenames,
  extractCharacters,
  isGenericCharacterName,
  resolveModelCharacterNames,
} from "./characters";
import { parseNovelText } from "./ingest";
import { buildOfflineAdaptation } from "./offline";
import {
  assessEpisodeScenes,
  recommendedScenes,
  runtimeBudget,
} from "./episodeBudget";

const fixture = `《测试小说》
作者：测试者

第1章 低谷
江南站在夜市里吆喝：“便宜卖了！”
王林踢翻摊位：“你也配跟我争？”
江南握紧拳头：“我偏要试试。”

第2章 反击
江南看向王林。王林冷笑，江南却忽然觉醒了系统。
“现在轮到我了。”江南说。
王林后退一步：“这不可能！”
江南走上前：“没有什么不可能。”`;

const options: AdaptationOptions = {
  episodeCount: 2,
  durationSeconds: 60,
  scenesPerEpisode: 2,
  genre: "都市逆袭",
  tone: "高燃轻喜",
  trendPreset: "精品爽剧",
};

describe("小说改编管线", () => {
  it("按章节拆解且保留完整文本", () => {
    const document = parseNovelText(fixture, "fixture.txt");
    expect(document.title).toBe("测试小说");
    expect(document.author).toBe("测试者");
    expect(document.chapters).toHaveLength(2);
    expect(document.chapters[1].title).toBe("反击");
  });

  it("长名字优先替换，避免部分串名", () => {
    expect(
      applyRenames("李慕言和李响", [
        {
          id: "1",
          sourceName: "李慕言",
          targetName: "苏清禾",
          role: "角色",
          traits: [],
          occurrences: 2,
          locked: true,
        },
        {
          id: "2",
          sourceName: "李响",
          targetName: "陆沉舟",
          role: "角色",
          traits: [],
          occurrences: 2,
          locked: true,
        },
      ]),
    ).toBe("苏清禾和陆沉舟");
  });

  it("模型返回角色8一类占位名时会生成唯一的安全姓名", () => {
    const sourceCharacters = Array.from({ length: 8 }, (_, index) => ({
      id: `character-${index + 1}`,
      sourceName: `原著人物${index + 1}`,
      targetName: "",
      role: index === 0 ? "核心主角" : "关键配角",
      traits: [],
      occurrences: 10 - index,
      locked: false,
    }));
    const resolved = resolveModelCharacterNames(
      sourceCharacters,
      sourceCharacters.map((character, index) => ({
        sourceName: character.sourceName,
        targetName: index === 7 ? "角色8" : ["周骁", "林妍", "顾川", "苏清禾", "贺砚", "秦越", "裴峥"][index],
      })),
    );

    expect(resolved).toHaveLength(8);
    expect(new Set(resolved.map((character) => character.targetName)).size).toBe(8);
    expect(
      resolved.every(
        (character) => !isGenericCharacterName(character.targetName),
      ),
    ).toBe(true);
  });

  it("生成完整集场并清除旧名", () => {
    const document = parseNovelText(fixture, "fixture.txt");
    const characters = extractCharacters(document, 2);
    const result = buildOfflineAdaptation(document, characters, options);
    const content = result.episodes.map((episode) => episode.content).join("\n");
    expect(result.episodes).toHaveLength(2);
    expect(result.episodes.every((episode) => episode.scenes.length === 2)).toBe(
      true,
    );
    expect(
      characters.every((character) => !content.includes(character.sourceName)),
    ).toBe(true);
    expect(
      result.quality.metrics.some((metric) => metric.id === "completeness"),
    ).toBe(true);
  });

  it("60秒规格会形成可执行的场次与字数预算", () => {
    const budget = runtimeBudget(options);
    expect(recommendedScenes(60)).toBe(2);
    expect(budget.spokenCharacters.min).toBe(129);
    expect(budget.spokenCharacters.max).toBe(195);
    expect(budget.scriptCharacters.min).toBe(222);
    expect(budget.minDialogueLines).toBe(12);
    expect(budget.maxDialogueLines).toBe(18);
  });

  it("会拒绝对白集中、角色过多的提纲式成稿", () => {
    const assessment = assessEpisodeScenes(
      [
        {
          heading: "外景 日",
          location: "裂缝",
          action: "主角踉跄走出裂缝，红衣女子站在不远处冷笑。",
          dialogue: [
            { speaker: "甲", text: "别忘了约定。" },
            { speaker: "乙", text: "我要先回宗门。" },
            { speaker: "甲", text: "我等不了太久。" },
          ],
        },
        {
          heading: "内景 日",
          location: "大殿",
          action: "五位师兄并排而立，主角单膝跪地自证身份。",
          dialogue: [
            { speaker: "乙", text: "是我，我回来了。" },
            { speaker: "丙", text: "你怎么证明？" },
            { speaker: "丁", text: "记得小时候的事吗？" },
            { speaker: "戊", text: "修为还在吗？" },
            { speaker: "己", text: "回来就好。" },
            { speaker: "庚", text: "我们养你。" },
          ],
        },
      ],
      options,
    );
    expect(assessment.passed).toBe(false);
    expect(assessment.speakingCharacters).toBeGreaterThan(
      runtimeBudget(options).maxSpeakingCharacters,
    );
    expect(assessment.issues.join("")).toContain("发言角色");
  });
});
