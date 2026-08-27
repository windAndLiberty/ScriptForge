import Foundation

struct EpisodeRuntimeBudget: Hashable, Sendable {
    let durationSeconds: Int
    let sceneRange: ClosedRange<Int>
    let spokenCharacters: ClosedRange<Int>
    let targetSpokenCharacters: Int
    let dialogueLines: ClosedRange<Int>
    let maxDialogueCharactersPerLine: Int
    let maxSpeakingCharacters: Int
}

struct EpisodeCompleteness: Hashable, Sendable {
    let score: Int
    let passed: Bool
    let issues: [String]
    let runtime: EpisodeRuntimeEstimate
}

enum EpisodeBudget {
    static func sceneRange(durationSeconds: Int) -> ClosedRange<Int> {
        if durationSeconds <= 60 { return 1...3 }
        if durationSeconds <= 90 { return 1...4 }
        if durationSeconds <= 120 { return 2...5 }
        return 2...6
    }

    static func budget(
        durationSeconds: Int,
        language: AppLanguage = .chinese
    ) -> EpisodeRuntimeBudget {
        let duration = max(30, durationSeconds)
        let minLines = max(6, Int((Double(duration) / 5.0).rounded()))
        let maxLines = max(minLines + 3, Int((Double(duration) / 3.3).rounded()))
        let spokenRange: ClosedRange<Int>
        let targetSpoken: Int
        let maxLineLength: Int
        if language == .english {
            spokenRange = Int(Double(duration) * 1.75)...Int(Double(duration) * 2.75)
            targetSpoken = Int(Double(duration) * 2.25)
            maxLineLength = duration <= 60 ? 14 : 18
        } else {
            spokenRange = Int(Double(duration) * 2.15)...Int(Double(duration) * 3.25)
            targetSpoken = Int(Double(duration) * 2.7)
            maxLineLength = duration <= 60 ? 18 : 22
        }
        return EpisodeRuntimeBudget(
            durationSeconds: duration,
            sceneRange: sceneRange(durationSeconds: duration),
            spokenCharacters: spokenRange,
            targetSpokenCharacters: targetSpoken,
            dialogueLines: minLines...maxLines,
            maxDialogueCharactersPerLine: maxLineLength,
            maxSpeakingCharacters: min(5, max(3, Int(ceil(Double(duration) / 45.0)) + 2))
        )
    }

    static func readableCharacters(_ value: String) -> Int {
        value.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }.count
    }

    static func estimateRuntime(
        scenes: [ScriptScene],
        language: AppLanguage = .chinese
    ) -> EpisodeRuntimeEstimate {
        let dialogue = scenes.flatMap(\.dialogue)
        let spokenCharacters = dialogue.reduce(0) {
            $0 + spokenUnits($1.text, language: language)
        }
        let unitsPerSecond = language == .english ? 2.5 : 4.2
        let speechSeconds = Double(spokenCharacters) / unitsPerSecond
            + dialogue.reduce(0.0) { $0 + punctuationPause($1.text) }
        let actionBeats = scenes.reduce(0) { $0 + actionBeatCount($1.action) }
        let performanceSeconds = Double(dialogue.count) * 0.3 + Double(actionBeats) * 0.85
        let transitionSeconds = Double(max(0, scenes.count - 1)) * 1.2
        let estimated = rounded(speechSeconds + performanceSeconds + transitionSeconds)
        return EpisodeRuntimeEstimate(
            estimatedSeconds: estimated,
            speechSeconds: rounded(speechSeconds),
            performanceSeconds: rounded(performanceSeconds),
            transitionSeconds: rounded(transitionSeconds),
            dialogueLines: dialogue.count,
            spokenCharacters: spokenCharacters,
            longDialogueLines: dialogue.filter {
                spokenUnits($0.text, language: language) > (language == .english ? 14 : 18)
            }.count,
            actionBeats: actionBeats
        )
    }

    static func assess(
        scenes: [ScriptScene],
        durationSeconds: Int,
        language: AppLanguage = .chinese
    ) -> EpisodeCompleteness {
        let target = budget(durationSeconds: durationSeconds, language: language)
        let runtime = estimateRuntime(scenes: scenes, language: language)
        let hasInsufficientDialogue = runtime.dialogueLines < target.dialogueLines.lowerBound ||
            runtime.spokenCharacters < target.spokenCharacters.lowerBound
        var issues: [String] = []
        var score = 100

        if !target.sceneRange.contains(scenes.count) {
            issues.append("Let the story determine scene count within \(target.sceneRange.lowerBound)–\(target.sceneRange.upperBound) scenes; the draft has \(scenes.count).")
            score -= 20
        }
        if runtime.dialogueLines < target.dialogueLines.lowerBound {
            issues.append("The episode has too little dialogue: target at least about \(target.dialogueLines.lowerBound) lines; the draft has \(runtime.dialogueLines).")
            score -= 24
        } else if runtime.dialogueLines > target.dialogueLines.upperBound {
            issues.append("The episode dialogue is too dense: target no more than about \(target.dialogueLines.upperBound) lines; the draft has \(runtime.dialogueLines).")
            score -= 14
        }
        if runtime.spokenCharacters < target.spokenCharacters.lowerBound {
            let unit = language == .english ? "English words" : "effective spoken Chinese characters"
            issues.append("The dialogue is too short: target at least about \(target.spokenCharacters.lowerBound) \(unit); the draft has \(runtime.spokenCharacters).")
            score -= 24
        } else if runtime.spokenCharacters > target.spokenCharacters.upperBound {
            let unit = language == .english ? "English words" : "effective spoken Chinese characters"
            issues.append("The dialogue is too long: target no more than about \(target.spokenCharacters.upperBound) \(unit); the draft has \(runtime.spokenCharacters).")
            score -= 14
        }
        let lowerRuntime = Double(durationSeconds) * 0.82
        let upperRuntime = Double(durationSeconds) * 1.18
        if runtime.estimatedSeconds < lowerRuntime {
            issues.append("Estimated performance time is too short: about \(runtime.estimatedSeconds) seconds versus a \(durationSeconds)-second target.")
            score -= 18
        } else if runtime.estimatedSeconds > upperRuntime {
            issues.append("Estimated performance time is too long: about \(runtime.estimatedSeconds) seconds versus a \(durationSeconds)-second target.")
            score -= 18
        }
        let speakers = Set(scenes.flatMap(\.dialogue).map(\.speaker).filter { !$0.isEmpty })
        if speakers.count > target.maxSpeakingCharacters {
            issues.append("There are too many primary speaking characters: target no more than \(target.maxSpeakingCharacters); the draft has \(speakers.count).")
            score -= 10
        }
        if runtime.longDialogueLines > max(1, runtime.dialogueLines / 5) {
            issues.append("Too many dialogue lines are long; split them into shorter exchanges with clearer opposition and response.")
            score -= 10
        }
        if scenes.contains(where: { readableCharacters($0.action) < 18 }) {
            issues.append("At least one scene lacks visible action, leaving performers and camera without a playable beat.")
            score -= 12
        }

        let bounded = max(0, min(100, score))
        return EpisodeCompleteness(
            score: bounded,
            passed: bounded >= 78 && !hasInsufficientDialogue,
            issues: issues,
            runtime: runtime
        )
    }

    private static func punctuationPause(_ value: String) -> Double {
        let strong = value.filter { "。！？!?…".contains($0) }.count
        let weak = value.filter { "，、；：,;:".contains($0) }.count
        return Double(strong) * 0.22 + Double(weak) * 0.1
    }

    private static func spokenUnits(_ value: String, language: AppLanguage) -> Int {
        guard language == .english else { return readableCharacters(value) }
        return value.split { character in
            !character.isLetter && !character.isNumber && character != "'" && character != "’"
        }.count
    }

    private static func actionBeatCount(_ value: String) -> Int {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let parts = value.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let verbs = "走冲退跪抬转抓扔摔拔推拉按点燃灭亮黑笑哭看盯递接挡劈刺震响开关落起停撕烧倒撞握松藏露挥闪"
        let verbCount = value.filter { verbs.contains($0) }.count
        return max(1, min(12, max(parts.count, Int(ceil(Double(verbCount) / 2.0)))))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
