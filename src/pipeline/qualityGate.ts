import type {
  Episode,
  QualityGateIssue,
  QualityGateReport,
  QualityGateTraceStep,
  QualityIssueCategory,
  QualityIssueSeverity,
} from "../domain";

export interface EpisodeAuditWindow {
  id: string;
  episodeNumbers: number[];
  episodes: Episode[];
}

export interface RawQualityGateIssue {
  id?: string;
  severity: QualityIssueSeverity;
  category: QualityIssueCategory;
  episodeNumbers: number[];
  evidence: string;
  repairInstruction: string;
}

export interface WindowAuditResult {
  passed: boolean;
  score: number;
  issues: RawQualityGateIssue[];
}

const ISSUE_CATEGORIES = new Set<QualityIssueCategory>([
  "source_fidelity",
  "continuity",
  "character",
  "pacing",
  "hook",
  "dialogue",
  "production",
  "compliance",
]);
const ISSUE_SEVERITIES = new Set<QualityIssueSeverity>([
  "blocker",
  "major",
  "minor",
]);

function compact(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function issueSignature(issue: {
  category: QualityIssueCategory;
  episodeNumbers: number[];
  evidence: string;
}) {
  return [
    issue.category,
    [...new Set(issue.episodeNumbers)].sort((a, b) => a - b).join(","),
    compact(issue.evidence).slice(0, 120),
  ].join("|");
}

export function buildEpisodeAuditWindows(
  episodes: Episode[],
  windowSize = 4,
): EpisodeAuditWindow[] {
  if (!episodes.length) return [];
  const safeWindowSize = Math.max(2, Math.floor(windowSize));
  const stride = Math.max(1, safeWindowSize - 1);
  const windows: EpisodeAuditWindow[] = [];
  for (let start = 0; start < episodes.length; start += stride) {
    const items = episodes.slice(start, start + safeWindowSize);
    if (!items.length) break;
    windows.push({
      id: `window-${items[0].number}-${items.at(-1)?.number}`,
      episodeNumbers: items.map((episode) => episode.number),
      episodes: items,
    });
    if (start + safeWindowSize >= episodes.length) break;
  }
  return windows;
}

export function normalizeWindowAuditIssues(
  audits: WindowAuditResult[],
  episodeCount: number,
) {
  const seen = new Set<string>();
  const normalized: QualityGateIssue[] = [];
  for (const audit of audits) {
    for (const [position, issue] of (audit.issues || []).entries()) {
      if (
        !ISSUE_SEVERITIES.has(issue.severity) ||
        !ISSUE_CATEGORIES.has(issue.category)
      ) {
        continue;
      }
      const episodeNumbers = [
        ...new Set(
          (issue.episodeNumbers || []).filter(
            (episode) =>
              Number.isInteger(episode) &&
              episode >= 1 &&
              episode <= episodeCount,
          ),
        ),
      ].sort((left, right) => left - right);
      const evidence = compact(issue.evidence || "");
      const repairInstruction = compact(issue.repairInstruction || "");
      if (!episodeNumbers.length || !evidence || !repairInstruction) continue;
      const candidate: QualityGateIssue = {
        id: compact(issue.id || "") || `audit-${normalized.length + position + 1}`,
        severity: issue.severity,
        category: issue.category,
        episodeNumbers,
        evidence,
        repairInstruction,
        status: "open",
      };
      const signature = issueSignature(candidate);
      if (seen.has(signature)) continue;
      seen.add(signature);
      normalized.push(candidate);
    }
  }
  return normalized;
}

export function buildIssueLedger(
  initialIssues: QualityGateIssue[],
  finalIssues: QualityGateIssue[],
) {
  const finalSignatures = new Set(finalIssues.map(issueSignature));
  const ledger = initialIssues.map((issue) => ({
    ...issue,
    status: finalSignatures.has(issueSignature(issue))
      ? ("open" as const)
      : ("resolved" as const),
  }));
  const initialSignatures = new Set(initialIssues.map(issueSignature));
  for (const issue of finalIssues) {
    if (!initialSignatures.has(issueSignature(issue))) {
      ledger.push({ ...issue, status: "open" });
    }
  }
  return ledger;
}

export function buildQualityGateReport(params: {
  deterministicScore: number;
  deterministicPassed: boolean;
  initialIssues: QualityGateIssue[];
  finalIssues: QualityGateIssue[];
  finalAuditsPassed: boolean;
  auditedWindows: number;
  repairAttempts: number;
  acceptedRepairs: number;
  trace: QualityGateTraceStep[];
}): QualityGateReport {
  const ledger = buildIssueLedger(params.initialIssues, params.finalIssues);
  const openIssues = ledger.filter((issue) => issue.status === "open");
  const hasBlockingIssue = openIssues.some(
    (issue) => issue.severity === "blocker" || issue.severity === "major",
  );
  const passed =
    params.deterministicPassed &&
    params.finalAuditsPassed &&
    !hasBlockingIssue;
  return {
    version: "trusted-quality-gate-v1",
    status: passed ? "passed" : "needs_review",
    deterministicScore: params.deterministicScore,
    auditedWindows: params.auditedWindows,
    repairAttempts: params.repairAttempts,
    acceptedRepairs: params.acceptedRepairs,
    openIssueCount: openIssues.length,
    issues: ledger,
    trace: [
      ...params.trace,
      {
        id: "delivery-gate",
        stage: "delivery_gate",
        status: passed ? "passed" : "failed",
        episodeNumbers: [],
        detail: passed
          ? "程序硬指标、跨集语义审片和修复复验均达到交付线"
          : `仍有 ${openIssues.length} 项开放问题，已阻止自动标记为可交付`,
      },
    ],
  };
}

export function episodeRepairQueue(
  issues: QualityGateIssue[],
  maxRepairs = 8,
) {
  const severityRank: Record<QualityIssueSeverity, number> = {
    blocker: 3,
    major: 2,
    minor: 1,
  };
  return [
    ...new Set(
      issues
        .filter((issue) => issue.severity !== "minor")
        .sort(
          (left, right) =>
            severityRank[right.severity] - severityRank[left.severity],
        )
        .flatMap((issue) => issue.episodeNumbers),
    ),
  ].slice(0, Math.max(0, maxRepairs));
}
