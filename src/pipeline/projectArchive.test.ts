import { describe, expect, it } from "vitest";
import type { StoredProject } from "../domain";
import {
  archiveProject,
  deleteArchivedProject,
  enforceRecentProjectLimit,
  MAX_RECENT_PROJECTS,
  restoreProject,
  upsertProject,
} from "./projectArchive";

function project(index: number): StoredProject {
  return {
    id: `project-${index}`,
    name: `项目 ${index}`,
    document: null,
    characters: [],
    options: {
      episodeCount: 8,
      durationSeconds: 60,
      scenesPerEpisode: 2,
      genre: "测试",
      tone: "测试",
      trendPreset: "精品爽剧",
    },
    result: null,
    phase: "idle",
    updatedAt: new Date(Date.UTC(2026, 0, index + 1)).toISOString(),
  };
}

describe("项目档案归档机制", () => {
  it("最近项目最多保留50个，多出的旧项目自动归档", () => {
    const projects = Array.from(
      { length: MAX_RECENT_PROJECTS + 3 },
      (_, index) => project(index),
    );
    const result = enforceRecentProjectLimit(
      projects,
      "2026-07-28T00:00:00.000Z",
    );
    expect(result.filter((item) => !item.archivedAt)).toHaveLength(50);
    expect(result.filter((item) => item.archivedAt)).toHaveLength(3);
    expect(result.find((item) => item.id === "project-0")?.archivedAt).toBeTruthy();
  });

  it("主动归档不会删除项目，并可恢复到最近项目", () => {
    const archived = archiveProject(
      [project(1), project(2)],
      "project-2",
      "2026-07-28T01:00:00.000Z",
    );
    expect(archived).toHaveLength(2);
    expect(archived.find((item) => item.id === "project-2")?.archivedAt).toBeTruthy();

    const restored = restoreProject(
      archived,
      "project-2",
      "2026-07-28T02:00:00.000Z",
    );
    expect(restored.find((item) => item.id === "project-2")?.archivedAt).toBeUndefined();
    expect(restored[0].id).toBe("project-2");
  });

  it("自动保存已归档项目时不会把它悄悄恢复", () => {
    const archived = archiveProject(
      [project(1)],
      "project-1",
      "2026-07-28T01:00:00.000Z",
    );
    const snapshot = {
      ...project(1),
      name: "归档后继续编辑",
      updatedAt: "2026-07-28T03:00:00.000Z",
    };
    const result = upsertProject(archived, snapshot);
    expect(result[0].name).toBe("归档后继续编辑");
    expect(result[0].archivedAt).toBe("2026-07-28T01:00:00.000Z");
  });

  it("只允许永久删除已归档项目", () => {
    const archived = archiveProject(
      [project(1), project(2)],
      "project-2",
      "2026-07-28T01:00:00.000Z",
    );

    const activeDeleteAttempt = deleteArchivedProject(archived, "project-1");
    expect(activeDeleteAttempt).toHaveLength(2);

    const result = deleteArchivedProject(archived, "project-2");
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("project-1");
  });
});
