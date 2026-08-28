import { describe, expect, it } from "vitest";
import type {
  BookAnalysisCharacter,
  BookAnalysisReport,
  NovelDocument,
} from "../domain";
import {
  buildOfflineBookAnalysis,
  chunkNovelForBookAnalysis,
  renderBookAnalysisMarkdown,
  runOnlineBookAnalysis,
} from "./bookAnalysis";
import type { StructuredCaller } from "./modelRouter";

function documentFixture(): NovelDocument {
  const chapters = [
    {
      id: "chapter-1",
      index: 1,
      title: "归来",
      content:
        "陈青云从天渊归来，发现魂灯重新燃起。他记得百年前的暗算，也决定先查清真相。" +
        "这是第一章结尾标记。",
      charCount: 52,
    },
    {
      id: "chapter-2",
      index: 2,
      title: "退婚",
      content:
        "东雪瑶提出退婚，陈青云碰到赔礼灵脉时察觉追魂印，林道远的线索第一次浮现。" +
        "这是第二章结尾标记。",
      charCount: 50,
    },
    {
      id: "chapter-3",
      index: 3,
      title: "剑气",
      content:
        "魂灯吸收残留剑气，陈青云恢复一层修为，也确认百年前那一剑来自林道远。" +
        "这是第三章结尾标记。",
      charCount: 48,
    },
  ];
  return {
    fileName: "fixture.txt",
    title: "魂灯归来",
    author: "测试作者",
    intro: "百年前被暗算的强者归来追查真相。",
    rawText: chapters.map((chapter) => chapter.content).join("\n"),
    charCount: chapters.reduce((total, chapter) => total + chapter.charCount, 0),
    chapters,
  };
}

const protagonist: BookAnalysisCharacter = {
  name: "陈青云",
  identity: "百年前的宗门强者",
  narrativeFunction: "推动复仇与真相线",
  motivation: "查明暗算真相",
  arc: "从修为尽废到重新掌握力量",
  relationships: ["与林道远敌对"],
  evidenceChapterIds: ["chapter-1", "chapter-3"],
};

function structureFixture(): BookAnalysisReport["structure"] {
  return {
    classification: "归来复仇+悬疑查案",
    openingHook: "魂灯重燃建立视觉奇观和生死悬念",
    rhythmOverview: "前两章蓄力，第三章完成第一次能力兑现",
    phases: [
      {
        name: "归来建局",
        chapterRange: "1—3章",
        rhythm: "连续升级",
        description: "身份确认、退婚冲突、剑气实证逐层推进。",
        highlightDensity: "三章一次显著兑现",
        evidenceChapterIds: ["chapter-1", "chapter-2", "chapter-3"],
      },
    ],
    foreshadowing: [],
    strengths: ["前三章信息持续升级"],
    risks: ["退婚桥段容易类型化"],
  };
}

function commercialFixture(): Pick<
  BookAnalysisReport,
  "title" | "meta" | "highlights" | "style" | "learning"
> {
  const technique = {
    name: "视觉钩子",
    observation: "用魂灯重燃承载归来信息",
    reusableMethod: "用一个可反复出现的道具绑定主线悬念",
    evidenceChapterIds: ["chapter-1", "chapter-3"],
  };
  return {
    title: "魂灯归来",
    meta: {
      sourceTitle: "魂灯归来",
      author: "测试作者",
      charCount: 150,
      chapterCount: 3,
      genreTags: ["玄幻", "复仇"],
      logline: "百年前被暗算的强者借魂灯重修并追查凶手。",
      targetReader: "偏好玄幻逆袭与阴谋线的读者",
      summary: "陈青云归来后从退婚赔礼中发现凶手线索，并借魂灯恢复力量。",
    },
    highlights: {
      overview: "核心爽点来自被轻视后的能力实证与真相逼近。",
      categories: [
        {
          type: "逆袭",
          intensity: "强烈",
          mechanism: "先确认修为尽废，再用魂灯恢复形成反差。",
          representativeScenes: ["魂灯吸收剑气"],
          evidenceChapterIds: ["chapter-1", "chapter-3"],
        },
      ],
      peakZone: "第3章",
      droughtZone: "暂无",
      averageInterval: "约3章一次",
      signatureMoments: ["魂灯重燃", "剑气实证"],
      strengths: ["视觉符号明确"],
      risks: ["需要避免连续口头放狠话"],
    },
    style: {
      language: "短句推进，重视动作结果。",
      narration: "第三人称近距离叙事。",
      sceneWriting: "道具与动作承担信息揭示。",
      dialogue: "对抗性强。",
      emotionalControl: "先压后扬。",
      techniques: [technique],
    },
    learning: {
      techniques: [technique],
      structureBlueprint: ["视觉异象", "公开冲突", "能力实证"],
      imitationDirections: ["更换世界观和道具，保留递进方法"],
      pitfalls: ["不要重复退婚羞辱"],
      score: 8,
      recommendation: "适合学习前三章连续升级。",
    },
  };
}

describe("一键拆书管线", () => {
  it("按叙事边界覆盖全部章节，长章不会被截断", () => {
    const chunks = chunkNovelForBookAnalysis(documentFixture(), 45);
    expect(chunks.length).toBeGreaterThan(3);
    expect(new Set(chunks.flatMap((chunk) => chunk.chapterIds))).toEqual(
      new Set(["chapter-1", "chapter-2", "chapter-3"]),
    );
    const combined = chunks.map((chunk) => chunk.content).join("\n");
    expect(combined).toContain("这是第一章结尾标记");
    expect(combined).toContain("这是第二章结尾标记");
    expect(combined).toContain("这是第三章结尾标记");
  });

  it("离线基础报告包含六个完整模块并可导出 Markdown", () => {
    const result = buildOfflineBookAnalysis(documentFixture(), [
      {
        id: "character-1",
        sourceName: "陈青云",
        targetName: "程青",
        role: "主角",
        traits: ["克制"],
        occurrences: 6,
        locked: true,
      },
    ]);
    expect(result.coveragePercent).toBe(100);
    expect(result.report.structure.phases.length).toBeGreaterThan(0);
    expect(result.report.characters.protagonist.name).toBe("陈青云");
    const markdown = renderBookAnalysisMarkdown(result);
    [
      "## 一、书籍元信息",
      "## 二、叙事结构深度分析",
      "## 三、人物体系分析",
      "## 四、爽点与卖点深度分析",
      "## 五、文笔与写作技法分析",
      "## 六、学习与仿写实操指南",
    ].forEach((heading) => expect(markdown).toContain(heading));
  });

  it("系统固定使用 Flash 抽取、Pro 完成三个专项判断", async () => {
    const routes: Array<{ name: string; route?: "primary" | "flash" }> = [];
    const instructions: string[] = [];
    const callStructured: StructuredCaller = async <T,>(payload: {
      name: string;
      route?: "primary" | "flash";
      instructions: string;
    }) => {
      routes.push({ name: payload.name, route: payload.route });
      instructions.push(payload.instructions);
      if (payload.name === "book_analysis_extract") {
        return {
          chapterIds: ["chapter-1", "chapter-2", "chapter-3"],
          summary: "陈青云归来后发现暗算线索。",
          plotBeats: ["魂灯重燃", "退婚冲突", "剑气实证"],
          characterMoves: ["陈青云从被动确认身份转向主动查凶"],
          hooks: ["魂灯为何重燃"],
          highlights: ["恢复第一层修为"],
          foreshadowing: ["林道远剑气"],
          styleSignals: ["动作道具承担信息"],
          uncertainties: [],
        } as T;
      }
      if (payload.name === "book_analysis_structure") {
        return structureFixture() as T;
      }
      if (payload.name === "book_analysis_characters") {
        return {
          protagonist,
          antagonists: [],
          supporting: [],
          relationshipOverview: "陈青云与林道远形成追凶关系。",
          evaluation: "主角目标明确，反派证据仍待扩展。",
        } as T;
      }
      return commercialFixture() as T;
    };

    const result = await runOnlineBookAnalysis({
      document: documentFixture(),
      characters: [],
      outputLanguage: "English",
      callStructured,
    });
    expect(result.mode).toBe("online");
    expect(result.report.structure.classification).toContain("复仇");
    expect(result.outputLanguage).toBe("English");
    expect(instructions.every((value) => value.includes("English"))).toBe(true);
    expect(
      routes.find((item) => item.name === "book_analysis_extract")?.route,
    ).toBe("flash");
    [
      "book_analysis_structure",
      "book_analysis_characters",
      "book_analysis_commercial",
    ].forEach((name) => {
      expect(routes.find((item) => item.name === name)?.route).toBe("primary");
    });
  });
});
