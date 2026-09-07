import type { CreativeWorkspace } from "./creative/types";

export type PipelinePhase =
  | "idle"
  | "ingest"
  | "analysis"
  | "characters"
  | "bible"
  | "outline"
  | "drafting"
  | "quality"
  | "completed"
  | "failed";

export interface Chapter {
  id: string;
  index: number;
  title: string;
  content: string;
  charCount: number;
}

export interface NovelDocument {
  fileName: string;
  title: string;
  author: string;
  intro: string;
  rawText: string;
  charCount: number;
  chapters: Chapter[];
}

export interface CharacterProfile {
  id: string;
  sourceName: string;
  targetName: string;
  role: string;
  traits: string[];
  occurrences: number;
  locked: boolean;
  nameSource?: "local" | "model" | "manual";
}

export interface AdaptationOptions {
  episodeCount: number;
  durationSeconds: number;
  scenesPerEpisode: number;
  genre: string;
  tone: string;
  trendPreset: "精品爽剧" | "现实共鸣" | "轻喜反转";
}

export interface DialogueLine {
  speaker: string;
  text: string;
}

export interface ScriptScene {
  id: string;
  heading: string;
  location: string;
  action: string;
  dialogue: DialogueLine[];
}

export interface CanonicalCharacter {
  id: string;
  sourceNames: string[];
  scriptName: string;
  role: string;
  relationships: string[];
  evidenceChapterIds: string[];
}

export interface WorldRule {
  id: string;
  subject: string;
  fact: string;
  cause: string;
  evidenceChapterIds: string[];
}

export interface PropThread {
  id: string;
  name: string;
  dramaticFunction: string;
  introducedEpisode: number;
  payoffEpisode: number;
  currentState: string;
  evidenceChapterIds: string[];
}

export interface TimelineEvent {
  id: string;
  order: number;
  location: string;
  time: string;
  participants: string[];
  cause: string;
  event: string;
  effect: string;
  evidenceChapterIds: string[];
}

export interface StoryBible {
  premise: string;
  canonicalCharacters: CanonicalCharacter[];
  worldRules: WorldRule[];
  propThreads: PropThread[];
  timeline: TimelineEvent[];
}

export interface EpisodeContract {
  dominantConflict: string;
  newInformation: string[];
  visualHook: string;
  transitionFromPrevious: string;
  activePropThreads: string[];
  entryState: string;
  exitState: string;
}

export interface EpisodeRuntimeEstimate {
  estimatedSeconds: number;
  speechSeconds: number;
  performanceSeconds: number;
  transitionSeconds: number;
  dialogueLines: number;
  spokenCharacters: number;
  longDialogueLines: number;
  actionBeats: number;
}

export interface EpisodeSemanticAudit {
  score: number;
  passed: boolean;
  issues: string[];
}

export interface Episode {
  id: string;
  number: number;
  title: string;
  sourceChapterIds: string[];
  plannedSceneCount?: number;
  openingHook: string;
  objective: string;
  reversal: string;
  endHook: string;
  contract?: EpisodeContract;
  runtime?: EpisodeRuntimeEstimate;
  semanticAudit?: EpisodeSemanticAudit;
  scenes: ScriptScene[];
  content: string;
}

export interface QualityMetric {
  id: string;
  label: string;
  score: number;
  detail: string;
  level: "good" | "warn" | "bad";
}

export type QualityIssueSeverity = "blocker" | "major" | "minor";

export type QualityIssueCategory =
  | "source_fidelity"
  | "continuity"
  | "character"
  | "pacing"
  | "hook"
  | "dialogue"
  | "production"
  | "compliance";

export interface QualityGateIssue {
  id: string;
  severity: QualityIssueSeverity;
  category: QualityIssueCategory;
  episodeNumbers: number[];
  evidence: string;
  repairInstruction: string;
  status: "open" | "resolved";
}

export interface QualityGateTraceStep {
  id: string;
  stage:
    | "deterministic_precheck"
    | "window_audit"
    | "targeted_repair"
    | "verification"
    | "delivery_gate";
  status: "passed" | "failed" | "accepted" | "rejected";
  episodeNumbers: number[];
  detail: string;
}

export interface QualityGateReport {
  version: "trusted-quality-gate-v1";
  status: "passed" | "needs_review";
  deterministicScore: number;
  auditedWindows: number;
  repairAttempts: number;
  acceptedRepairs: number;
  openIssueCount: number;
  issues: QualityGateIssue[];
  trace: QualityGateTraceStep[];
}

export interface QualityReport {
  score: number;
  metrics: QualityMetric[];
  warnings: string[];
  passed: boolean;
  gate?: QualityGateReport;
}

export interface AdaptationResult {
  logline: string;
  genre: string;
  themes: string[];
  sourceFacts: string[];
  storyBible?: StoryBible;
  episodes: Episode[];
  quality: QualityReport;
  generatedAt: string;
  mode: "offline" | "online";
}

export interface StoryboardShot {
  id: string;
  number: number;
  sceneId: string;
  title: string;
  durationSeconds: number;
  shotSize: string;
  cameraMovement: string;
  composition: string;
  visualAction: string;
  dialogue: string;
  narration: string;
  soundEffects: string;
  imagePrompt: string;
  negativePrompt: string;
  continuityNotes: string;
  productionNotes: string;
  keyframePath?: string;
  narrationPath?: string;
}

export interface EpisodeStoryboard {
  episodeNumber: number;
  title: string;
  aspectRatio: "9:16";
  visualStyle: string;
  characterVisualAnchors: string[];
  shots: StoryboardShot[];
}

export interface ProductionPackage {
  version: "storyboard-v1";
  createdAt: string;
  mode: "offline" | "online";
  episodes: EpisodeStoryboard[];
}

export interface BookAnalysisPhase {
  name: string;
  chapterRange: string;
  rhythm: string;
  description: string;
  highlightDensity: string;
  evidenceChapterIds: string[];
}

export interface BookAnalysisForeshadowing {
  content: string;
  planted: string;
  revealed: string;
  quality: string;
  evidenceChapterIds: string[];
}

export interface BookAnalysisCharacter {
  name: string;
  identity: string;
  narrativeFunction: string;
  motivation: string;
  arc: string;
  relationships: string[];
  evidenceChapterIds: string[];
}

export interface BookAnalysisHighlightCategory {
  type: string;
  intensity: string;
  mechanism: string;
  representativeScenes: string[];
  evidenceChapterIds: string[];
}

export interface BookAnalysisTechnique {
  name: string;
  observation: string;
  reusableMethod: string;
  evidenceChapterIds: string[];
}

export interface BookAnalysisReport {
  title: string;
  meta: {
    sourceTitle: string;
    author: string;
    charCount: number;
    chapterCount: number;
    genreTags: string[];
    logline: string;
    targetReader: string;
    summary: string;
  };
  structure: {
    classification: string;
    openingHook: string;
    rhythmOverview: string;
    phases: BookAnalysisPhase[];
    foreshadowing: BookAnalysisForeshadowing[];
    strengths: string[];
    risks: string[];
  };
  characters: {
    protagonist: BookAnalysisCharacter;
    antagonists: BookAnalysisCharacter[];
    supporting: BookAnalysisCharacter[];
    relationshipOverview: string;
    evaluation: string;
  };
  highlights: {
    overview: string;
    categories: BookAnalysisHighlightCategory[];
    peakZone: string;
    droughtZone: string;
    averageInterval: string;
    signatureMoments: string[];
    strengths: string[];
    risks: string[];
  };
  style: {
    language: string;
    narration: string;
    sceneWriting: string;
    dialogue: string;
    emotionalControl: string;
    techniques: BookAnalysisTechnique[];
  };
  learning: {
    techniques: BookAnalysisTechnique[];
    structureBlueprint: string[];
    imitationDirections: string[];
    pitfalls: string[];
    score: number;
    recommendation: string;
  };
}

export interface BookAnalysisVersion {
  id: string;
  instruction: string;
  createdAt: string;
  report: BookAnalysisReport;
}

export interface BookAnalysisResult {
  report: BookAnalysisReport;
  versions: BookAnalysisVersion[];
  currentVersion: number;
  generatedAt: string;
  mode: "offline" | "online";
  totalChunks: number;
  analyzedChunks: number;
  coveragePercent: number;
  warnings: string[];
  outputLanguage?: "Simplified Chinese" | "English";
}

export interface StoredProject {
  schemaVersion?: 5;
  id: string;
  qualityProfileVersion?: number;
  archivedAt?: string;
  name: string;
  document: NovelDocument | null;
  characters: CharacterProfile[];
  options: AdaptationOptions;
  result: AdaptationResult | null;
  bookAnalysis?: BookAnalysisResult | null;
  productionPackage?: ProductionPackage | null;
  creativeWorkspace?: CreativeWorkspace;
  phase: PipelinePhase;
  updatedAt: string;
}
