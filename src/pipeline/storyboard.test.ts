import { describe, expect, it } from "vitest";
import type { AdaptationResult } from "../domain";
import { buildOfflineStoryboard, renderStoryboardMarkdown } from "./storyboard";

describe("storyboard pipeline", () => {
  it("creates normalized production shots from approved scenes", () => {
    const result = { logline: "", genre: "Drama", themes: [], sourceFacts: [], episodes: [{ id: "e1", number: 1, title: "Arrival", sourceChapterIds: [], openingHook: "A door opens", objective: "Enter", reversal: "Locked", endHook: "A voice", scenes: [{ id: "s1", heading: "INT. ROOM", location: "Room", action: "Mara enters.", dialogue: [{ speaker: "Mara", text: "Hello?" }] }], content: "EP 1" }], quality: { score: 100, metrics: [], warnings: [], passed: true }, generatedAt: new Date().toISOString(), mode: "offline" } satisfies AdaptationResult;
    const value = buildOfflineStoryboard(result, [{ id: "c1", sourceName: "Mara", targetName: "Mara", role: "lead", traits: ["dark coat"], occurrences: 1, locked: true }], 60);
    expect(value.episodes[0].shots).toHaveLength(2);
    expect(value.episodes[0].shots.reduce((sum, shot) => sum + shot.durationSeconds, 0)).toBe(60);
    expect(value.episodes[0].shots[0].imagePrompt).toContain("9:16");
    expect(renderStoryboardMarkdown(value, "Sample")).toContain("Keyframe prompt");
  });
});
