import { describe, expect, it } from "vitest";
import { DEFAULT_PROMPT_ASSETS } from "./promptAssets";

describe("default prompt assets", () => {
  it("ships model instructions in English only", () => {
    expect(DEFAULT_PROMPT_ASSETS).toHaveLength(6);
    for (const asset of DEFAULT_PROMPT_ASSETS) {
      expect(asset.content).not.toMatch(/[\u3400-\u9fff]/);
      expect(asset.content.length).toBeGreaterThan(80);
    }
  });
});
