export type CreativeWorkflowId =
  | "incubation"
  | "storyBible"
  | "outline"
  | "chapterProduction"
  | "continuityAudit"
  | "chapterPolish";

export type WorkflowRunStatus =
  | "queued"
  | "running"
  | "waitingForModel"
  | "waitingForApproval"
  | "interrupted"
  | "failed"
  | "completed"
  | "cancelled";

export type WorkflowStepStatus =
  | "pending"
  | "running"
  | "waiting"
  | "completed"
  | "failed"
  | "skipped";

export type WorkflowStepKind = "local" | "model" | "approval" | "validation";
export type ModelRoute = "primary" | "flash";
export type CreativeArtifactKind =
  | "brief"
  | "storyBible"
  | "outline"
  | "chapterCards"
  | "chapterDraft"
  | "auditReport"
  | "polishedChapter"
  | "handoff"
  | "promptSnapshot";

export interface CreativeGenerationItem {
  kind: string;
  name: string;
  summary: string;
  content: string;
  details: string[];
}

export interface CreativeGenerationPayload {
  title: string;
  summary: string;
  markdown: string;
  items: CreativeGenerationItem[];
}

export interface CreativeBrief {
  id: string;
  title: string;
  genre: string;
  targetAudience: string;
  premise: string;
  sellingPoints: string[];
  protagonist: string;
  centralConflict: string;
  tone: string;
  constraints: string[];
  createdAt: string;
}

export type StoryBibleCardKind =
  | "character"
  | "worldRule"
  | "location"
  | "faction"
  | "item"
  | "ability"
  | "style";

export interface StoryBibleCard {
  id: string;
  kind: StoryBibleCardKind;
  name: string;
  summary: string;
  details: Record<string, string>;
  aliases: string[];
  visibility: "included" | "hidden";
  sourceChapterNumbers: number[];
}

export interface CreativeStoryBible {
  id: string;
  title: string;
  cards: StoryBibleCard[];
  styleGuide: string;
  forbiddenElements: string[];
  createdAt: string;
}

export interface ChapterCard {
  id: string;
  number: number;
  volumeNumber: number;
  title: string;
  objective: string;
  conflict: string;
  reveal: string;
  hook: string;
  sceneBeats: string[];
  activeForeshadowingIds: string[];
}

export interface VolumeOutline {
  id: string;
  number: number;
  title: string;
  arcSummary: string;
  chapterCards: ChapterCard[];
  createdAt: string;
}

export type ChapterStatus = "planned" | "drafting" | "review" | "accepted";
export type ChapterVersionSource =
  | "imported"
  | "generated"
  | "polished"
  | "manual"
  | "restored";

export interface ChapterVersion {
  id: string;
  createdAt: string;
  source: ChapterVersionSource;
  contentPath: string;
  summary: string;
  wordCount: number;
  promptSnapshotId?: string;
  accepted: boolean;
}

export interface ChapterDocument {
  id: string;
  number: number;
  volumeNumber: number;
  title: string;
  cardId?: string;
  status: ChapterStatus;
  currentVersionId?: string;
  candidateVersionId?: string;
  versions: ChapterVersion[];
}

export interface CreativeCharacterState {
  id: string;
  characterName: string;
  chapterNumber: number;
  location: string;
  physicalState: string;
  emotionalState: string;
  knowledge: string[];
  possessions: string[];
  abilities: string[];
}

export interface CreativeTimelineEvent {
  id: string;
  chapterNumber: number;
  timeLabel: string;
  location: string;
  participants: string[];
  event: string;
}

export interface ForeshadowingRecord {
  id: string;
  title: string;
  plantedChapter: number;
  expectedPayoffChapter?: number;
  paidOffChapter?: number;
  status: "active" | "paidOff" | "abandoned";
  detail: string;
}

export interface ContinuityIssue {
  id: string;
  severity: "info" | "warning" | "blocker";
  category: string;
  chapterNumbers: number[];
  evidence: string;
  suggestion: string;
}

export interface WorkflowInputField {
  id: string;
  label: string;
  required: boolean;
  defaultValue?: string;
}

export interface WorkflowStepDefinition {
  id: string;
  title: string;
  kind: WorkflowStepKind;
  optional?: boolean;
  route?: ModelRoute;
}

export interface WorkflowDefinition {
  id: CreativeWorkflowId;
  title: string;
  summary: string;
  inputFields: WorkflowInputField[];
  steps: WorkflowStepDefinition[];
  artifactKinds: CreativeArtifactKind[];
}

export interface WorkflowRunInput {
  seed: string;
  instruction: string;
  batchCount: number;
  selectedChapterIds: string[];
  parameters: Record<string, string>;
  disabledStepIds: string[];
  excludedContextIds: string[];
}

export interface WorkflowStepRun {
  id: string;
  title: string;
  kind: WorkflowStepKind;
  status: WorkflowStepStatus;
  startedAt?: string;
  completedAt?: string;
  error?: string;
  artifactIds: string[];
}

export interface WorkflowRun {
  id: string;
  workflowId: CreativeWorkflowId;
  status: WorkflowRunStatus;
  input: WorkflowRunInput;
  inputSnapshot: string;
  steps: WorkflowStepRun[];
  activeStepIndex: number;
  artifactIds: string[];
  promptSnapshotId?: string;
  modelId?: string;
  error?: string;
  createdAt: string;
  updatedAt: string;
}

export interface WorkflowRunReference {
  id: string;
  workflowId: CreativeWorkflowId;
  status: WorkflowRunStatus;
  path: string;
  updatedAt: string;
}

export interface WorkflowArtifactReference {
  id: string;
  runId: string;
  workflowId: CreativeWorkflowId;
  kind: CreativeArtifactKind;
  title: string;
  summary: string;
  contentPath: string;
  isCandidate: boolean;
  createdAt: string;
}

export interface CreativePromptRevision {
  id: string;
  instruction: string;
  createdAt: string;
}

export interface CreativePromptOverride {
  workflowId: CreativeWorkflowId;
  instruction: string;
  revisions: CreativePromptRevision[];
  updatedAt: string;
}

export interface CreativePromptSnapshot {
  id: string;
  workflowId: CreativeWorkflowId;
  systemVersion: string;
  workflowRevisionId?: string;
  projectInstruction: string;
  runInstruction: string;
  assembledPrompt: string;
  contextLabels: string[];
  createdAt: string;
}

export interface CreativeContextOption {
  id: string;
  label: string;
  content: string;
  included: boolean;
}

export interface CreativeHandoffSnapshot {
  id: string;
  createdAt: string;
  chapterVersionIds: string[];
  sourceTextPath: string;
}

export interface CreativeWorkspace {
  projectInstruction: string;
  briefs: CreativeBrief[];
  activeBriefId?: string;
  storyBibles: CreativeStoryBible[];
  activeStoryBibleId?: string;
  outlines: VolumeOutline[];
  chapters: ChapterDocument[];
  characterStates: CreativeCharacterState[];
  timeline: CreativeTimelineEvent[];
  foreshadowing: ForeshadowingRecord[];
  continuityIssues: ContinuityIssue[];
  runs: WorkflowRunReference[];
  artifacts: WorkflowArtifactReference[];
  promptOverrides: CreativePromptOverride[];
  handoffs: CreativeHandoffSnapshot[];
  selectedChapterId?: string;
}

export function emptyCreativeWorkspace(): CreativeWorkspace {
  return {
    projectInstruction: "",
    briefs: [],
    storyBibles: [],
    outlines: [],
    chapters: [],
    characterStates: [],
    timeline: [],
    foreshadowing: [],
    continuityIssues: [],
    runs: [],
    artifacts: [],
    promptOverrides: [],
    handoffs: [],
  };
}
