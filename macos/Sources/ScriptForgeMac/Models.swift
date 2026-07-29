import Foundation

enum PipelinePhase: String, Codable, CaseIterable {
    case idle
    case ingest
    case analysis
    case characters
    case outline
    case drafting
    case quality
    case completed
    case failed
}

struct Chapter: Identifiable, Codable, Hashable {
    let id: String
    let index: Int
    let title: String
    let content: String
    let characterCount: Int
}

struct NovelDocument: Codable {
    let fileName: String
    let title: String
    let author: String
    let intro: String
    let rawText: String
    let characterCount: Int
    let chapters: [Chapter]
}

struct CharacterProfile: Identifiable, Codable, Hashable {
    let id: String
    let sourceName: String
    var targetName: String
    var role: String
    var traits: [String]
    let occurrences: Int
    var locked: Bool
}

enum TrendPreset: String, Codable, CaseIterable, Identifiable {
    case premium = "精品爽剧"
    case grounded = "现实共鸣"
    case comedy = "轻喜反转"

    var id: String { rawValue }
}

struct AdaptationOptions: Codable {
    var episodeCount = 8
    var durationSeconds = 90
    var scenesPerEpisode = 2
    var genre = "都市逆袭·热血轻喜"
    var tone = "高燃、机敏、轻喜"
    var trendPreset = TrendPreset.premium
}

struct DialogueLine: Identifiable, Codable, Hashable {
    var id: String { "\(speaker)|\(text)" }
    let speaker: String
    let text: String
}

struct ScriptScene: Identifiable, Codable, Hashable {
    let id: String
    let heading: String
    let location: String
    let action: String
    let dialogue: [DialogueLine]
}

struct Episode: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let title: String
    let sourceChapterIDs: [String]
    let openingHook: String
    let objective: String
    let reversal: String
    let endHook: String
    let scenes: [ScriptScene]
    var content: String
}

enum QualityLevel: String, Codable, Hashable {
    case good
    case warning
    case bad
}

struct QualityMetric: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let score: Int
    let detail: String
    let level: QualityLevel
}

struct QualityReport: Codable {
    let score: Int
    let metrics: [QualityMetric]
    let warnings: [String]
    let passed: Bool
}

enum GenerationMode: String, Codable {
    case offline
    case online
}

struct AdaptationResult: Codable {
    let logline: String
    let genre: String
    let themes: [String]
    let sourceFacts: [String]
    var episodes: [Episode]
    let quality: QualityReport
    let generatedAt: Date
    let mode: GenerationMode
}

struct ProjectState: Codable {
    var id = UUID()
    var name = "新建改编项目"
    var document: NovelDocument?
    var characters: [CharacterProfile] = []
    var options = AdaptationOptions()
    var result: AdaptationResult?
    var phase = PipelinePhase.idle
    var updatedAt = Date()
}

struct ModelSettings: Codable {
    var baseURL = "https://api.openai.com/v1"
    var model = "gpt-5.6-terra"
    var reasoningEffort = "low"
    var useOnline = false
}
