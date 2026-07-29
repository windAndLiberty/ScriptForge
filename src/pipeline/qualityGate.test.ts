import { describe, expect, it } from "vitest";
import type { Episode, QualityGateIssue } from "../domain";
import {
  buildEpisodeAuditWindows,
  buildQualityGateReport,
  episodeRepairQueue,
  normalizeWindowAuditIssues,
} from "./qualityGate";

function episode(number: number): Episode {
  return {
    id: `episode-${number}`,
    number,
    title: `第${number}集`,
    sourceChapterIds: [],
    openingHook: "钩子",
    objective: "目标",
    reversal: "反转",
    endHook: "卡点",
    scenes: [],
    content: "",
  };
}

function issue(
  id: string,
  severity: QualityGateIssue["severity"],
  episodeNumbers: number[],
): QualityGateIssue {
  return {
    id,
    severity,
    category: "continuity",
    episodeNumbers,
    evidence: `${id} evidence`,
    repairInstruction: `${id} repair`,
    status: "open",
  };
}

describe("可信质量门禁", () => {
  it("按重叠窗口审查长剧，避免跨窗口边界失去连续性", () => {
    const windows = buildEpisodeAuditWindows(
      Array.from({ length: 8 }, (_, index) => episode(index + 1)),
      4,
    );
    expect(windows.map((item) => item.episodeNumbers)).toEqual([
      [1, 2, 3, 4],
      [4, 5, 6, 7],
      [7, 8],
    ]);
  });

  it("规范化并去重模型问题，丢弃越界或无证据项", () => {
    const result = normalizeWindowAuditIssues(
      [
        {
          passed: false,
          score: 70,
          issues: [
            {
              id: "a",
              severity: "major",
              category: "continuity",
              episodeNumbers: [2, 2],
              evidence: " 第2集状态未承接 ",
              repairInstruction: "补足转场",
            },
            {
              id: "duplicate",
              severity: "major",
              category: "continuity",
              episodeNumbers: [2],
              evidence: "第2集状态未承接",
              repairInstruction: "补足转场",
            },
            {
              id: "invalid",
              severity: "blocker",
              category: "source_fidelity",
              episodeNumbers: [99],
              evidence: "越界",
              repairInstruction: "忽略",
            },
          ],
        },
      ],
      3,
    );
    expect(result).toHaveLength(1);
    expect(result[0].episodeNumbers).toEqual([2]);
  });

  it("只修复阻断与重大问题，并设置有界预算", () => {
    expect(
      episodeRepairQueue(
        [
          issue("minor", "minor", [1]),
          issue("major", "major", [2, 3]),
          issue("blocker", "blocker", [4, 5]),
        ],
        3,
      ),
    ).toEqual([4, 5, 2]);
  });

  it("开放重大问题会阻止自动交付，已消失的问题进入已解决台账", () => {
    const initial = [issue("fixed", "major", [1]), issue("open", "major", [2])];
    const report = buildQualityGateReport({
      deterministicScore: 92,
      deterministicPassed: true,
      initialIssues: initial,
      finalIssues: [initial[1]],
      finalAuditsPassed: false,
      auditedWindows: 2,
      repairAttempts: 1,
      acceptedRepairs: 1,
      trace: [],
    });
    expect(report.status).toBe("needs_review");
    expect(report.issues.find((item) => item.id === "fixed")?.status).toBe(
      "resolved",
    );
    expect(report.openIssueCount).toBe(1);
  });
});
