import { describe, expect, it } from "vitest";
import type { AdaptationOptions } from "../domain";
import {
  sanitizeAdaptationResult,
  sanitizeCharacters,
  sanitizeDocument,
} from "./projectMigration";

const options: AdaptationOptions = {
  episodeCount: 1,
  durationSeconds: 60,
  scenesPerEpisode: 3,
  genre: "都市逆袭",
  tone: "高燃",
  trendPreset: "精品爽剧",
};

describe("旧项目数据迁移", () => {
  it("缺少 scenes/dialogue 时不会再读取 undefined.length", () => {
    const result = sanitizeAdaptationResult(
      {
        logline: "测试",
        episodes: [
          {
            number: 1,
            title: "旧存档",
            scenes: [
              {
                heading: "内景 日",
                location: "大厅",
                action: "角色走进大厅。",
              },
            ],
          },
        ],
      },
      options,
      [],
    );
    expect(result?.episodes[0].scenes[0].dialogue).toEqual([]);
    expect(result?.quality.passed).toBe(false);
  });

  it("损坏的文档和人物数组会安全降级", () => {
    expect(sanitizeDocument({ title: "空项目" })).toBeNull();
    expect(sanitizeCharacters(undefined)).toEqual([]);
  });

  it("旧项目中的角色8占位名会恢复为待模型命名", () => {
    expect(
      sanitizeCharacters([
        {
          sourceName: "上官海",
          targetName: "角色8",
          role: "关键配角",
          locked: true,
        },
      ])[0],
    ).toMatchObject({
      sourceName: "上官海",
      targetName: "",
      locked: false,
    });
  });

  it("师兄师弟等关系称谓不会迁移成人物姓名", () => {
    expect(
      sanitizeCharacters([
        {
          sourceName: "师兄",
          targetName: "顾川",
          role: "关键配角",
          locked: true,
        },
        {
          sourceName: "程青",
          targetName: "程野",
          role: "核心主角",
          locked: true,
        },
      ]).map((character) => character.sourceName),
    ).toEqual(["程青"]);
  });
});
