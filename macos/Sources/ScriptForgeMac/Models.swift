import Foundation

enum PipelinePhase: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case ingest
    case naming
    case analysis
    case bible
    case outline
    case drafting
    case quality
    case completed
    case failed
}

enum PrimaryView: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bookAnalysis
    case studio
    case projects
    case prompts

    var id: String { rawValue }
}

struct Chapter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let index: Int
    let title: String
    let content: String
    let characterCount: Int
}

struct NovelDocument: Codable, Hashable, Sendable {
    let fileName: String
    let title: String
    let author: String
    let intro: String
    let rawText: String
    let characterCount: Int
    let chapters: [Chapter]
}

enum CharacterNameSource: String, Codable, Hashable, Sendable {
    case local
    case model
    case manual
}

struct CharacterProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceName: String
    var targetName: String
    var role: String
    var traits: [String]
    let occurrences: Int
    var locked: Bool
    var nameSource: CharacterNameSource
}

enum TrendPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case premium = "精品爽剧"
    case grounded = "现实共鸣"
    case comedy = "轻喜反转"

    var id: String { rawValue }
}

struct AdaptationOptions: Codable, Hashable, Sendable {
    var episodeCount = 8
    var durationSeconds = 60
    var genre = "玄幻逆袭"
    var tone = "高燃、克制、强反转"
    var trendPreset = TrendPreset.premium
}

struct DialogueLine: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(speaker)|\(text)" }
    let speaker: String
    let text: String
}

struct ScriptScene: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let heading: String
    let location: String
    let action: String
    let dialogue: [DialogueLine]
}

struct CanonicalCharacter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceNames: [String]
    let scriptName: String
    let role: String
    let relationships: [String]
    let evidenceChapterIDs: [String]
}

struct WorldRule: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let subject: String
    let fact: String
    let cause: String
    let evidenceChapterIDs: [String]
}

struct TimelineEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let order: Int
    let location: String
    let time: String
    let participants: [String]
    let cause: String
    let event: String
    let effect: String
    let evidenceChapterIDs: [String]
}

struct PropThread: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let dramaticFunction: String
    let introducedEpisode: Int
    let payoffEpisode: Int
    let currentState: String
    let evidenceChapterIDs: [String]
}

struct StoryBible: Codable, Hashable, Sendable {
    let premise: String
    let canonicalCharacters: [CanonicalCharacter]
    let worldRules: [WorldRule]
    let propThreads: [PropThread]
    let timeline: [TimelineEvent]
}

struct EpisodeContract: Codable, Hashable, Sendable {
    let dominantConflict: String
    let newInformation: [String]
    let visualHook: String
    let transitionFromPrevious: String
    let activePropThreads: [String]
    let entryState: String
    let exitState: String
}

struct EpisodeRuntimeEstimate: Codable, Hashable, Sendable {
    let estimatedSeconds: Double
    let speechSeconds: Double
    let performanceSeconds: Double
    let transitionSeconds: Double
    let dialogueLines: Int
    let spokenCharacters: Int
    let longDialogueLines: Int
    let actionBeats: Int
}

struct EpisodeSemanticAudit: Codable, Hashable, Sendable {
    let score: Int
    let passed: Bool
    let issues: [String]
}

struct Episode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let sourceChapterIDs: [String]
    let plannedSceneCount: Int
    let openingHook: String
    let objective: String
    let reversal: String
    let endHook: String
    let contract: EpisodeContract
    var runtime: EpisodeRuntimeEstimate?
    var semanticAudit: EpisodeSemanticAudit?
    var scenes: [ScriptScene]
    var content: String
}

enum QualityLevel: String, Codable, Hashable, Sendable {
    case good
    case warning
    case bad
}

struct QualityMetric: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let score: Int
    let detail: String
    let level: QualityLevel
}

enum QualityIssueSeverity: String, Codable, Hashable, Sendable {
    case blocker
    case major
    case minor
}

enum QualityIssueCategory: String, Codable, Hashable, Sendable {
    case sourceFidelity
    case continuity
    case character
    case pacing
    case hook
    case dialogue
    case production
    case compliance
}

struct QualityGateIssue: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let severity: QualityIssueSeverity
    let category: QualityIssueCategory
    let episodeNumbers: [Int]
    let evidence: String
    let repairInstruction: String
    var resolved: Bool
}

struct QualityGateTrace: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let stage: String
    let status: String
    let episodeNumbers: [Int]
    let detail: String
}

struct QualityGateReport: Codable, Hashable, Sendable {
    let version: String
    let status: String
    let deterministicScore: Int
    let auditedWindows: Int
    let repairAttempts: Int
    let acceptedRepairs: Int
    let issues: [QualityGateIssue]
    let trace: [QualityGateTrace]

    var openIssueCount: Int { issues.filter { !$0.resolved }.count }
}

struct QualityReport: Codable, Hashable, Sendable {
    let score: Int
    let metrics: [QualityMetric]
    let warnings: [String]
    let passed: Bool
    let gate: QualityGateReport?
}

enum GenerationMode: String, Codable, Hashable, Sendable {
    case offline
    case online
}

struct AdaptationResult: Codable, Hashable, Sendable {
    let logline: String
    let genre: String
    let themes: [String]
    let sourceFacts: [String]
    let storyBible: StoryBible
    var episodes: [Episode]
    let quality: QualityReport
    let generatedAt: Date
    let mode: GenerationMode
}

struct BookAnalysisSection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let markdown: String
    let evidenceChapterIDs: [String]
}

struct BookAnalysisReport: Codable, Hashable, Sendable {
    let title: String
    let logline: String
    let summary: String
    let genreTags: [String]
    let targetReader: String
    let sections: [BookAnalysisSection]
    let coveragePercent: Int
    let generatedAt: Date
    let mode: GenerationMode
}

struct BookAnalysisVersion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let instruction: String
    let createdAt: Date
    let report: BookAnalysisReport
}

struct PromptAsset: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let scope: String
    let influence: String
    var instruction: String
    var isDefault: Bool
    var updatedAt: Date
}

struct PipelineCheckpoint: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let phase: PipelinePhase
    let inputHash: String
    let promptVersion: String
    let completedAt: Date
}

struct StoredProject: Identifiable, Codable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    var id: UUID
    var schemaVersion: Int
    var name: String
    var document: NovelDocument?
    var characters: [CharacterProfile]
    var options: AdaptationOptions
    var result: AdaptationResult?
    var bookAnalysis: BookAnalysisReport?
    var bookAnalysisVersions: [BookAnalysisVersion]
    var checkpoints: [PipelineCheckpoint]
    var phase: PipelinePhase
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(name: String = "新建改编项目") {
        id = UUID()
        schemaVersion = Self.currentSchemaVersion
        self.name = name
        document = nil
        characters = []
        options = AdaptationOptions()
        result = nil
        bookAnalysis = nil
        bookAnalysisVersions = []
        checkpoints = []
        phase = .idle
        archivedAt = nil
        createdAt = Date()
        updatedAt = Date()
    }

    var hasContent: Bool {
        document != nil || result != nil || bookAnalysis != nil
    }

    var generatedEpisodeCount: Int { result?.episodes.count ?? 0 }
    var chapterCount: Int { document?.chapters.count ?? 0 }
}

struct ModelSettings: Codable, Hashable, Sendable {
    var baseURL = "https://api.openai.com/v1"
    var primaryModel = "gpt-5.6-sol"
    var flashModel = "gpt-5.6-terra"
    var reasoningEffort = "low"
    var useOnline = false
    var consentedEndpointHost = ""

    var endpointHost: String {
        URL(string: baseURL)?.host?.lowercased() ?? ""
    }

    var hasEndpointConsent: Bool {
        !endpointHost.isEmpty && consentedEndpointHost == endpointHost
    }
}

struct PipelineProgress: Codable, Hashable, Sendable {
    var phase = PipelinePhase.idle
    var detail = ""
    var fraction = 0.0
}

struct BookAnalysisProgress: Codable, Hashable, Sendable {
    var detail = ""
    var completed = 0
    var total = 0
    var fraction = 0.0
}
