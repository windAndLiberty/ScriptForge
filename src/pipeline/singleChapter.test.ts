import { describe, expect, it } from "vitest";
import {
  FIRST_PASS_PROMPT,
  SECOND_PASS_PROMPT,
  activeSingleChapterScript,
  emptySingleChapterWorkflow,
  formatStoryBoard,
  runFixedSingleChapterPipeline,
} from "./singleChapter";

describe("single chapter adaptation workflow", () => {
  it("keeps both pipeline prompts fixed", () => {
    expect(FIRST_PASS_PROMPT).toContain("爆款开头+结尾留钩");
    expect(SECOND_PASS_PROMPT).toContain("视频推文");
  });

  it("formats the user story board as one constraint block", () => {
    expect(
      formatStoryBoard({
        worldName: "雾城",
        worldBackground: "终年被雾笼罩",
        coreEntries: "林舟；铜钥匙",
        forbiddenWords: "系统",
      }),
    ).toContain("世界设定名称：雾城");
  });

  it("returns only the explicitly selected baseline version", () => {
    const workflow = emptySingleChapterWorkflow("chapter-1");
    workflow.versions = [
      { id: "old", createdAt: "now", content: "旧版", source: "generated" },
      { id: "new", createdAt: "now", content: "新版", source: "ai_revision" },
    ];
    workflow.activeVersionId = "old";
    expect(activeSingleChapterScript(workflow)).toBe("旧版");
  });

  it("feeds the first response into the second fixed model call", async () => {
    const calls: Array<{ instructions: string; input: string; name: string }> = [];
    const result = await runFixedSingleChapterPipeline({
      chapter: "原始章节",
      constraints: "故事板与改名表",
      call: async (instructions, input, name) => {
        calls.push({ instructions, input, name });
        return calls.length === 1 ? "第一次精简稿" : "最终剧本";
      },
    });
    expect(calls).toHaveLength(2);
    expect(calls[1].input).toContain("第一次精简稿");
    expect(calls[1].input).not.toContain("原始章节");
    expect(result.finalScript).toBe("最终剧本");
  });
});
