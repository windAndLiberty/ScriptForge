import { describe, expect, it } from "vitest";
import {
  callModelStage,
  modelPolicySnapshot,
  routeForStage,
} from "./modelRouter";

describe("系统级双模型调度", () => {
  it("高吞吐抽取与语义初审走快速模型", () => {
    expect(routeForStage("character_naming")).toBe("flash");
    expect(routeForStage("chapter_analysis")).toBe("flash");
    expect(routeForStage("episode_semantic_audit")).toBe("flash");
    expect(routeForStage("series_quality_audit")).toBe("flash");
    expect(routeForStage("book_analysis_extract")).toBe("flash");
    expect(routeForStage("book_analysis_digest")).toBe("flash");
  });

  it("全局创作决策、成稿和修复走高质量模型", () => {
    const policy = modelPolicySnapshot();
    [
      "story_bible",
      "story_bible_repair",
      "episode_outline",
      "episode_outline_repair",
      "episode_draft",
      "episode_repair",
      "series_quality_repair",
      "book_analysis_structure",
      "book_analysis_characters",
      "book_analysis_commercial",
      "book_analysis_revision",
    ].forEach((stage) => {
      expect(policy[stage as keyof typeof policy]).toBe("primary");
    });
  });

  it("调用方不能绕过阶段策略自行选择模型", async () => {
    let capturedRoute = "";
    await callModelStage(
      async <T,>(payload: { route?: "primary" | "flash" }): Promise<T> => {
        capturedRoute = payload.route || "";
        return { ok: true } as T;
      },
      "chapter_analysis",
      {
        instructions: "extract",
        input: "source",
        name: "chapter_analysis",
        schema: { type: "object" },
      },
    );
    expect(capturedRoute).toBe("flash");
  });
});
