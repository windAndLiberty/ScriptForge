import { createRequire } from "node:module";
import { describe, expect, it, vi } from "vitest";

const require = createRequire(import.meta.url);
const { applyUiScale, normalizeUiScale } = require("./ui-scale.cjs");

describe("desktop UI scale", () => {
  it("normalizes persisted and untrusted scale values", () => {
    expect(normalizeUiScale("1.2")).toBe(1.2);
    expect(normalizeUiScale(0.2)).toBe(0.85);
    expect(normalizeUiScale(4)).toBe(1.3);
    expect(normalizeUiScale("invalid")).toBe(1);
  });

  it("applies the normalized factor to Electron webContents", () => {
    const setZoomFactor = vi.fn();
    const webContents = { isDestroyed: () => false, setZoomFactor };
    expect(applyUiScale(webContents, 1.3000001)).toBe(1.3);
    expect(setZoomFactor).toHaveBeenCalledOnce();
    expect(setZoomFactor).toHaveBeenCalledWith(1.3);
  });

  it("does not touch a destroyed window", () => {
    expect(() =>
      applyUiScale({ isDestroyed: () => true, setZoomFactor: vi.fn() }, 1.1),
    ).toThrow("no longer available");
  });
});
