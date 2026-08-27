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
    case creation
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

enum SourceContentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case prose
    case screenplay

    var chineseLabel: String {
        return switch self {
        case .prose: "小说 / 故事"
        case .screenplay: "已有剧本"
        }
    }
}

enum SourceDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

struct SourceDiagnostic: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let severity: SourceDiagnosticSeverity
    let code: String
    let message: String
    let unitNumbers: [Int]
}

struct NovelDocument: Codable, Hashable, Sendable {
    let fileName: String
    let title: String
    let author: String
    let intro: String
    let rawText: String
    let characterCount: Int
    let chapters: [Chapter]
    let sourceKind: SourceContentKind?
    let diagnostics: [SourceDiagnostic]?

    init(
        fileName: String,
        title: String,
        author: String,
        intro: String,
        rawText: String,
        characterCount: Int,
        chapters: [Chapter],
        sourceKind: SourceContentKind = .prose,
        diagnostics: [SourceDiagnostic] = []
    ) {
        self.fileName = fileName
        self.title = title
        self.author = author
        self.intro = intro
        self.rawText = rawText
        self.characterCount = characterCount
        self.chapters = chapters
        self.sourceKind = sourceKind
        self.diagnostics = diagnostics
    }

    var resolvedSourceKind: SourceContentKind { sourceKind ?? .prose }
    var sourceDiagnostics: [SourceDiagnostic] { diagnostics ?? [] }
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

    func resolvedRole(for language: AppLanguage) -> String {
        guard language == .english else { return role }
        switch role {
        case "核心主角": return "Core Protagonist"
        case "主要角色": return "Main Character"
        case "关键配角": return "Key Supporting Character"
        default: return role
        }
    }
}

enum TrendPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case premium = "精品爽剧"
    case grounded = "现实共鸣"
    case comedy = "轻喜反转"

    var id: String { rawValue }

    func resolvedValue(for language: AppLanguage) -> String {
        guard language == .english else { return rawValue }
        return switch self {
        case .premium: "Premium Hook Drama"
        case .grounded: "Grounded Resonance"
        case .comedy: "Light Comedy"
        }
    }
}

struct AdaptationOptions: Codable, Hashable, Sendable {
    static let defaultGenreChinese = "玄幻逆袭"
    static let defaultGenreEnglish = "Fantasy Comeback"
    static let defaultToneChinese = "高燃、克制、强反转"
    static let defaultToneEnglish = "High-energy, restrained, with strong reversals"

    var episodeCount = 8
    var durationSeconds = 60
    var genre = Self.defaultGenreChinese
    var tone = Self.defaultToneChinese
    var trendPreset = TrendPreset.premium
    var preserveSourceLanguage = true
    var targetLanguage = AppLanguage.chinese

    private enum CodingKeys: String, CodingKey {
        case episodeCount, durationSeconds, genre, tone, trendPreset
        case preserveSourceLanguage, targetLanguage
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        episodeCount = try values.decodeIfPresent(Int.self, forKey: .episodeCount) ?? 8
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 60
        genre = try values.decodeIfPresent(String.self, forKey: .genre) ?? Self.defaultGenreChinese
        tone = try values.decodeIfPresent(String.self, forKey: .tone) ?? Self.defaultToneChinese
        trendPreset = try values.decodeIfPresent(TrendPreset.self, forKey: .trendPreset) ?? .premium
        preserveSourceLanguage = try values.decodeIfPresent(Bool.self, forKey: .preserveSourceLanguage) ?? true
        targetLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .targetLanguage) ?? .chinese
    }

    func outputLanguage(for document: NovelDocument) -> AppLanguage {
        preserveSourceLanguage ? AppLanguage.detect(in: document.rawText) : targetLanguage
    }

    func resolvedGenre(for language: AppLanguage) -> String {
        if language == .english, genre == Self.defaultGenreChinese { return Self.defaultGenreEnglish }
        if language == .chinese, genre == Self.defaultGenreEnglish { return Self.defaultGenreChinese }
        return genre
    }

    func resolvedTone(for language: AppLanguage) -> String {
        if language == .english, tone == Self.defaultToneChinese { return Self.defaultToneEnglish }
        if language == .chinese, tone == Self.defaultToneEnglish { return Self.defaultToneChinese }
        return tone
    }
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

struct StoryboardShot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let number: Int
    let sceneID: String
    let title: String
    let durationSeconds: Double
    let shotSize: String
    let cameraMovement: String
    let composition: String
    let visualAction: String
    let dialogue: String
    let narration: String
    let soundEffects: String
    let imagePrompt: String
    let negativePrompt: String
    let continuityNotes: String
    let productionNotes: String
    var keyframePath: String?
    var narrationPath: String?
}

struct EpisodeStoryboard: Identifiable, Codable, Hashable, Sendable {
    var id: Int { episodeNumber }
    let episodeNumber: Int
    let title: String
    let aspectRatio: String
    let visualStyle: String
    let characterVisualAnchors: [String]
    var shots: [StoryboardShot]

    var totalDurationSeconds: Double {
        shots.reduce(0) { $0 + $1.durationSeconds }
    }
}

struct ProductionPackage: Codable, Hashable, Sendable {
    static let currentVersion = "storyboard-v1"

    let version: String
    let createdAt: Date
    let mode: GenerationMode
    var episodes: [EpisodeStoryboard]

    var shotCount: Int { episodes.reduce(0) { $0 + $1.shots.count } }
}

struct BookAnalysisSection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let markdown: String
    let evidenceChapterIDs: [String]
}

struct BookAnalysisReport: Codable, Hashable, Sendable {
    let title: String
    let outputLanguage: AppLanguage?
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
    static let currentSchemaVersion = 5

    var id: UUID
    var schemaVersion: Int
    var name: String
    var document: NovelDocument?
    var characters: [CharacterProfile]
    var options: AdaptationOptions
    var result: AdaptationResult?
    var productionPackage: ProductionPackage?
    var bookAnalysis: BookAnalysisReport?
    var bookAnalysisVersions: [BookAnalysisVersion]
    var creativeWorkspace: CreativeWorkspace?
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
        productionPackage = nil
        bookAnalysis = nil
        bookAnalysisVersions = []
        creativeWorkspace = nil
        checkpoints = []
        phase = .idle
        archivedAt = nil
        createdAt = Date()
        updatedAt = Date()
    }

    var hasContent: Bool {
        document != nil || result != nil || productionPackage != nil || bookAnalysis != nil
            || creativeWorkspace != nil
    }

    var generatedEpisodeCount: Int { result?.episodes.count ?? 0 }
    var chapterCount: Int { document?.chapters.count ?? 0 }
    var sourceKind: SourceContentKind { document?.resolvedSourceKind ?? .prose }
}

struct ModelSettings: Codable, Hashable, Sendable {
    var baseURL = "https://api.openai.com/v1"
    var primaryModel = "gpt-5.6-sol"
    var flashModel = "gpt-5.6-terra"
    var reasoningEffort = "low"
    var imageModel = ""
    var speechModel = ""
    var speechVoice = "alloy"
    var useOnline = false
    var consentedEndpointHost = ""

    private enum CodingKeys: String, CodingKey {
        case baseURL, primaryModel, flashModel, reasoningEffort
        case imageModel, speechModel, speechVoice, useOnline, consentedEndpointHost
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.openai.com/v1"
        primaryModel = try values.decodeIfPresent(String.self, forKey: .primaryModel) ?? "gpt-5.6-sol"
        flashModel = try values.decodeIfPresent(String.self, forKey: .flashModel) ?? "gpt-5.6-terra"
        reasoningEffort = try values.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? "low"
        imageModel = try values.decodeIfPresent(String.self, forKey: .imageModel) ?? ""
        speechModel = try values.decodeIfPresent(String.self, forKey: .speechModel) ?? ""
        speechVoice = try values.decodeIfPresent(String.self, forKey: .speechVoice) ?? "alloy"
        useOnline = try values.decodeIfPresent(Bool.self, forKey: .useOnline) ?? false
        consentedEndpointHost = try values.decodeIfPresent(String.self, forKey: .consentedEndpointHost) ?? ""
    }

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
