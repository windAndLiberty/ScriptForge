import Foundation

enum CreativeWorkflowID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case incubation
    case storyBible
    case outline
    case chapterProduction
    case continuityAudit
    case chapterPolish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incubation: "新书孵化"
        case .storyBible: "故事圣经"
        case .outline: "卷章规划"
        case .chapterProduction: "章节生产"
        case .continuityAudit: "连贯性审计"
        case .chapterPolish: "章节精修"
        }
    }
}

enum WorkflowStepKind: String, Codable, Hashable, Sendable {
    case local
    case model
    case approval
    case validation
}

enum WorkflowRunStatus: String, Codable, Hashable, Sendable {
    case queued
    case running
    case waitingForModel
    case waitingForApproval
    case interrupted
    case failed
    case completed
    case cancelled
}

enum WorkflowStepStatus: String, Codable, Hashable, Sendable {
    case pending
    case running
    case waiting
    case completed
    case failed
    case skipped
}

enum CreativeArtifactKind: String, Codable, Hashable, Sendable {
    case brief
    case storyBible
    case outline
    case chapterCards
    case chapterDraft
    case auditReport
    case polishedChapter
    case handoff
    case promptSnapshot
}

enum ChapterStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case planned
    case drafting
    case review
    case accepted
}

enum ChapterVersionSource: String, Codable, Hashable, Sendable {
    case imported
    case generated
    case polished
    case manual
    case restored
}

enum StoryBibleCardKind: String, Codable, CaseIterable, Hashable, Sendable {
    case character
    case worldRule
    case location
    case faction
    case item
    case ability
    case style

    var title: String {
        switch self {
        case .character: "人物"
        case .worldRule: "世界规则"
        case .location: "地点"
        case .faction: "势力"
        case .item: "物品"
        case .ability: "能力"
        case .style: "文风"
        }
    }
}

enum StoryBibleVisibility: String, Codable, Hashable, Sendable {
    case included
    case hidden
}

enum ContinuitySeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case blocker
}

struct CreativeBrief: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var genre: String
    var targetAudience: String
    var premise: String
    var sellingPoints: [String]
    var protagonist: String
    var centralConflict: String
    var tone: String
    var constraints: [String]
    let createdAt: Date
}

struct StoryBibleCard: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: StoryBibleCardKind
    var name: String
    var summary: String
    var details: [String: String]
    var aliases: [String]
    var visibility: StoryBibleVisibility
    var sourceChapterNumbers: [Int]
}

struct CreativeStoryBible: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var cards: [StoryBibleCard]
    var styleGuide: String
    var forbiddenElements: [String]
    let createdAt: Date
}

struct ForeshadowingRecord: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case planned
        case active
        case paidOff
        case abandoned
    }

    let id: UUID
    var name: String
    var introducedChapter: Int
    var plannedPayoffChapter: Int?
    var actualPayoffChapter: Int?
    var status: Status
    var notes: String
}

struct CreativeCharacterState: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var characterName: String
    var location: String
    var condition: String
    var knowledge: [String]
    var possessions: [String]
    var abilities: [String]
    var updatedChapter: Int
}

struct CreativeTimelineEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var chapterNumber: Int
    var storyTime: String
    var location: String
    var participants: [String]
    var event: String
}

struct ChapterCard: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var number: Int
    var volumeNumber: Int
    var title: String
    var objective: String
    var conflict: String
    var reveal: String
    var hook: String
    var sceneBeats: [String]
    var activeForeshadowingIDs: [UUID]
}

struct VolumeOutline: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var number: Int
    var title: String
    var arcSummary: String
    var chapterCards: [ChapterCard]
    let createdAt: Date
}

struct ChapterVersion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let source: ChapterVersionSource
    let contentPath: String
    var summary: String
    var wordCount: Int
    var promptSnapshotID: UUID?
    var accepted: Bool
}

struct ChapterDocument: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var number: Int
    var volumeNumber: Int
    var title: String
    var cardID: UUID?
    var status: ChapterStatus
    var currentVersionID: UUID?
    var candidateVersionID: UUID?
    var versions: [ChapterVersion]
}

struct ContinuityIssue: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var severity: ContinuitySeverity
    var category: String
    var chapterNumbers: [Int]
    var evidence: String
    var suggestion: String
}

struct WorkflowInputField: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let placeholder: String
    let required: Bool
}

struct WorkflowStepDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: WorkflowStepKind
    let isOptional: Bool
    let modelRoute: ModelRoute?
}

struct WorkflowDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: CreativeWorkflowID
    let summary: String
    let symbol: String
    let inputFields: [WorkflowInputField]
    let steps: [WorkflowStepDefinition]
}

struct WorkflowRunInput: Codable, Hashable, Sendable {
    var seed = ""
    var instruction = ""
    var batchCount = 1
    var selectedChapterIDs: [UUID] = []
    var parameters: [String: String] = [:]
    var disabledStepIDs: Set<String> = []
    var excludedContextIDs: Set<String> = []
}

struct WorkflowStepRun: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: WorkflowStepKind
    var status: WorkflowStepStatus
    var startedAt: Date?
    var completedAt: Date?
    var artifactIDs: [UUID]
    var errorMessage: String?
}

struct WorkflowRun: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let workflowID: CreativeWorkflowID
    var status: WorkflowRunStatus
    var input: WorkflowRunInput
    var steps: [WorkflowStepRun]
    var activeStepIndex: Int
    var artifactIDs: [UUID]
    var promptSnapshotID: UUID?
    var modelNames: [ModelRoute: String]
    var endpointHost: String?
    let createdAt: Date
    var updatedAt: Date
    var errorMessage: String?
}

struct WorkflowRunReference: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let workflowID: CreativeWorkflowID
    var status: WorkflowRunStatus
    var updatedAt: Date
}

struct WorkflowArtifactReference: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let runID: UUID
    let workflowID: CreativeWorkflowID
    let kind: CreativeArtifactKind
    var title: String
    var summary: String
    let contentPath: String
    var isCandidate: Bool
    let createdAt: Date
}

struct CreativePromptRevision: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let instruction: String
    let createdAt: Date
}

struct CreativePromptOverride: Identifiable, Codable, Hashable, Sendable {
    var id: CreativeWorkflowID { workflowID }
    let workflowID: CreativeWorkflowID
    var instruction: String
    var revisions: [CreativePromptRevision]
    var updatedAt: Date
}

struct CreativePromptSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let workflowID: CreativeWorkflowID
    let systemVersion: String
    let workflowRevisionID: UUID?
    let projectInstruction: String
    let runInstruction: String
    let assembledPrompt: String
    let contextLabels: [String]
    let createdAt: Date
}

struct CreativeContextOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

struct CreativeHandoffSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let chapterVersionIDs: [UUID]
    let document: NovelDocument
}

struct CreativeWorkspace: Codable, Hashable, Sendable {
    var briefs: [CreativeBrief] = []
    var activeBriefID: UUID?
    var storyBibles: [CreativeStoryBible] = []
    var activeStoryBibleID: UUID?
    var outlines: [VolumeOutline] = []
    var chapters: [ChapterDocument] = []
    var characterStates: [CreativeCharacterState] = []
    var timeline: [CreativeTimelineEvent] = []
    var foreshadowing: [ForeshadowingRecord] = []
    var continuityIssues: [ContinuityIssue] = []
    var runReferences: [WorkflowRunReference] = []
    var artifacts: [WorkflowArtifactReference] = []
    var projectPromptInstructions: [CreativeWorkflowID: String] = [:]
    var handoffSnapshots: [CreativeHandoffSnapshot] = []
    var selectedChapterID: UUID?

    var activeBrief: CreativeBrief? {
        briefs.first(where: { $0.id == activeBriefID }) ?? briefs.last
    }

    var activeStoryBible: CreativeStoryBible? {
        storyBibles.first(where: { $0.id == activeStoryBibleID }) ?? storyBibles.last
    }

    var activeOutline: VolumeOutline? { outlines.last }
}

struct CreativeGenerationPayload: Codable, Hashable, Sendable {
    struct Item: Codable, Hashable, Sendable {
        let kind: String
        let name: String
        let summary: String
        let content: String
        let details: [String]
    }

    let title: String
    let summary: String
    let markdown: String
    let items: [Item]
}

struct CreativeProjectExport: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let projectName: String
    let brief: CreativeBrief?
    let storyBible: CreativeStoryBible?
    let outlines: [VolumeOutline]
    let chapters: [CreativeExportChapter]
    let characterStates: [CreativeCharacterState]
    let timeline: [CreativeTimelineEvent]
    let foreshadowing: [ForeshadowingRecord]
    let exportedAt: Date
}

struct CreativeExportChapter: Codable, Hashable, Sendable {
    let number: Int
    let volumeNumber: Int
    let title: String
    let content: String
    let versionID: UUID
}

enum CreativeExportFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case docx
    case markdown
    case json

    var id: String { rawValue }
}
