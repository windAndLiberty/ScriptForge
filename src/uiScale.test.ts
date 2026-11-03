import { describe, expect, it } from "vitest";
import { normalizeUiScale, stepUiScale } from "./uiScale";

describe("UI scale controls", () => {
  it("normalizes saved values to a supported zoom stop", () => {
    expect(normalizeUiScale("0.85")).toBe(0.85);
    expect(normalizeUiScale(0.97)).toBe(1);
    expect(normalizeUiScale("invalid")).toBe(1);
  });

  it("can always return from the minimum scale to 100%", () => {
    expect(stepUiScale(0.85, 1)).toBe(0.9);
    expect(stepUiScale(0.9, 1)).toBe(1);
  });

  it("clamps stepping at both ends", () => {
    expect(stepUiScale(0.85, -1)).toBe(0.85);
    expect(stepUiScale(1.3, 1)).toBe(1.3);
  });
});
