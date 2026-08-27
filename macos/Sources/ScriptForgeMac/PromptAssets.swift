import Foundation
import CryptoKit

enum PromptAssets {
    static let version = "mac-prompts-v4-en"

    static let defaults: [PromptAsset] = [
        PromptAsset(
            id: "story-evidence",
            title: "Story Evidence Extraction",
            scope: "Chapter analysis and the evidence layer for Book Analysis",
            influence: "Controls which characters, events, causal links, and foreshadowing elements are retained from the source; it does not directly set screenplay style.",
            instruction: """
            Extract only facts explicitly supported by the source. Every fact must retain its chapter evidence ID. Distinguish completed events, character motivations, world rules, and unresolved foreshadowing. Do not add information absent from the source.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "character-naming",
            title: "Lightweight Character Renaming",
            scope: "Flash-model naming call after import",
            influence: "Controls new screenplay character names. Manually edited names have the highest priority and must not be changed by later model calls.",
            instruction: """
            Generate natural Chinese names that fit each character's personality and the conventions of Chinese short-form drama. Each name must contain two to four Chinese characters, be unique, differ from the source name, and never use placeholders such as "Character 8" or "Male Lead 1."
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "story-bible",
            title: "Story Bible and Continuity",
            scope: "Series facts, relationships, timeline, and prop continuity",
            influence: "Constrains character identity, relationships, ability rules, location changes, and foreshadowing payoffs across all episodes; it is the canonical source for continuity decisions.",
            instruction: """
            Organize chapter evidence into an actionable story bible. Reconcile character identities and aliases, state the causes and limits of world rules, and build a causally ordered timeline. Never present unsupported material as established fact.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "episode-planning",
            title: "Chinese Vertical-Drama Episode Planning",
            scope: "Series-wide episode contracts and per-episode scene recommendations",
            influence: "Controls each episode's new event, opening hook, reversal, closing cliffhanger, and dynamic scene count; it does not draft complete dialogue.",
            instruction: """
            Advance one central conflict per episode while adding new information or causing a new consequence. Show a visible conflict within the first five seconds and end the final five to eight seconds on an unfinished action or information gap. Within the first three episodes, establish the situation, a humiliation or crisis, and an ability or truth reversal. Never repeat the same conflict across consecutive episodes. Let the story determine scene count; a 60-second episode normally uses one to three scenes.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "episode-drafting",
            title: "Shootable Episode Draft",
            scope: "Per-episode scene action and dialogue",
            influence: "Directly controls pacing, visible action, dialogue density, and the closing cliffhanger in the final screenplay.",
            instruction: """
            Draft a production-ready vertical micro-drama episode for the Chinese market. Every action must be visible, shootable, and give performers a playable reaction. Keep dialogue short and adversarial; never restate an action the audience has just seen. A 60-second episode normally contains 12–18 dialogue lines, preferably no more than 18 Chinese characters per line. Do not split scenes merely to increase the count. End at the exact moment an action, discovery, or choice occurs.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "quality-gate",
            title: "Evidence-Grounded Quality Gate",
            scope: "Episode review, series audit, issue ledger, and targeted repair",
            influence: "Determines whether a draft passes and identifies repair locations; it must not rewrite valid content merely to increase a score.",
            instruction: """
            Use evidence to check source fidelity, character continuity, motivation, time and location transitions, conflict progression, opening and closing hooks, and shootability. Report only issues with a precise location. During repair, address only blocker and major issues while preserving scenes and dialogue that already work.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "storyboard-production",
            title: "Storyboard and Multimedia Production Package",
            scope: "Approved screenplay to shots, keyframes, sound, and continuity notes",
            influence: "Controls shot breakdown, composition, camera movement, sound design, and image prompts without changing the approved story.",
            instruction: """
            Break the approved screenplay into executable shots. Every shot must specify shot size, camera movement, vertical composition, visible action, dialogue or narration, sound, continuity, and production notes. Total shot duration must match the episode target. Each keyframe prompt must repeat stable character visual anchors and specify 9:16. Do not add characters, events, locations, prop abilities, or outcomes absent from the screenplay.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        PromptAsset(
            id: "book-analysis",
            title: "Six-Section Book Analysis",
            scope: "Structure, characters, commercial payoffs, style, techniques, and adaptation guidance",
            influence: "Controls the depth and evidence standard of the analysis report; it does not directly modify the screenplay draft.",
            instruction: """
            The book analysis must cover six sections: content overview, structure and pacing, character system, commercial highlights, language and style, and reusable techniques. Every judgment must cite chapter evidence IDs. Clearly distinguish source facts, analytical inferences, and adaptation recommendations.
            """,
            isDefault: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    // Hashes allow old built-in defaults to migrate without shipping their obsolete prompt text.
    private static let legacyDefaultHashes: [String: String] = [
        "story-evidence": "f5b356263bab21ae72baad20086e8b0a21fc95a1658b2339c62f7bc2e5996b1e",
        "character-naming": "4eefac4b6513b21e62ebd235eb18e08d8929c86369ed06973b8e681a065bee39",
        "story-bible": "10b34c08e82fadd8d5ad6d0592ea19fa48e3f2da2fab3f7f2e519aecc7a65b49",
        "episode-planning": "d1009c1a1d53d3f53941b2311b51ece1226e34ec8465deebb2b26678ee03d82b",
        "episode-drafting": "fbfe098b3cab1fa8f6bbb4a7fccae2fe337fbdb7872e3f7b474a5d3618b276f9",
        "quality-gate": "833a0f4add1b081c4a02130f156e0444b2fdb87382d22a6e2793e8702762d3b6",
        "storyboard-production": "f2821351fc758be5c217554c325850d6fc8f05114f74912e4388312f7848e323",
        "book-analysis": "e99298dbfcc41ce056a976b0c816e7869109c77270d2e81487bccd0df689cf7f",
    ]

    static func mergedInstruction(_ ids: [String], assets: [PromptAsset]) -> String {
        ids.compactMap { id in assets.first(where: { $0.id == id })?.instruction }
            .joined(separator: "\n\n")
    }

    static func reset(asset: PromptAsset) -> PromptAsset {
        defaults.first(where: { $0.id == asset.id }) ?? asset
    }

    static func isLegacyDefault(_ asset: PromptAsset) -> Bool {
        guard let expected = legacyDefaultHashes[asset.id] else { return false }
        let normalized = asset.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return digest == expected
    }
}

final class PromptAssetRepository {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil) {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ScriptForge", isDirectory: true)
        fileURL = root.appendingPathComponent("prompt-assets.json")
        encoder = JSONEncoder.scriptForge
        decoder = JSONDecoder.scriptForge
    }

    func load() -> [PromptAsset] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let saved = try? decoder.decode([PromptAsset].self, from: data)
        else { return PromptAssets.defaults }
        let merged = PromptAssets.defaults.map { defaultAsset in
            guard let savedAsset = saved.first(where: { $0.id == defaultAsset.id }) else {
                return defaultAsset
            }
            guard !savedAsset.isDefault, !PromptAssets.isLegacyDefault(savedAsset) else {
                return defaultAsset
            }
            return PromptAsset(
                id: defaultAsset.id,
                title: defaultAsset.title,
                scope: defaultAsset.scope,
                influence: defaultAsset.influence,
                instruction: savedAsset.instruction,
                isDefault: false,
                updatedAt: savedAsset.updatedAt
            )
        }
        if merged != saved { try? save(merged) }
        return merged
    }

    func save(_ assets: [PromptAsset]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(assets).write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var scriptForge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var scriptForge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
