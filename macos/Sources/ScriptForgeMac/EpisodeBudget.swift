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

    static func budget(durationSeconds: Int) -> EpisodeRuntimeBudget {
        let duration = max(30, durationSeconds)
        let minLines = max(6, Int((Double(duration) / 5.0).rounded()))
        let maxLines = max(minLines + 3, Int((Double(duration) / 3.3).rounded()))
        return EpisodeRuntimeBudget(
            durationSeconds: duration,
            sceneRange: sceneRange(durationSeconds: duration),
            spokenCharacters: Int(Double(duration) * 2.15)...Int(Double(duration) * 3.25),
            targetSpokenCharacters: Int(Double(duration) * 2.7),
            dialogueLines: minLines...maxLines,
            maxDialogueCharactersPerLine: duration <= 60 ? 18 : 22,
            maxSpeakingCharacters: min(5, max(3, Int(ceil(Double(duration) / 45.0)) + 2))
        )
    }

    static func readableCharacters(_ value: String) -> Int {
        value.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }.count
    }

    static func estimateRuntime(scenes: [ScriptScene]) -> EpisodeRuntimeEstimate {
        let dialogue = scenes.flatMap(\.dialogue)
        let spokenCharacters = dialogue.reduce(0) { $0 + readableCharacters($1.text) }
        let speechSeconds = Double(spokenCharacters) / 4.2
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
            longDialogueLines: dialogue.filter { readableCharacters($0.text) > 18 }.count,
            actionBeats: actionBeats
        )
    }

    static func assess(scenes: [ScriptScene], durationSeconds: Int) -> EpisodeCompleteness {
        let target = budget(durationSeconds: durationSeconds)
        let runtime = estimateRuntime(scenes: scenes)
        var issues: [String] = []
        var score = 100

        if !target.sceneRange.contains(scenes.count) {
            issues.append("场次数应由剧情在 \(target.sceneRange.lowerBound)–\(target.sceneRange.upperBound) 场内动态决定，实际 \(scenes.count) 场")
            score -= 20
        }
        if runtime.dialogueLines < target.dialogueLines.lowerBound {
            issues.append("整集对白不足：至少约 \(target.dialogueLines.lowerBound) 句，实际 \(runtime.dialogueLines) 句")
            score -= 24
        } else if runtime.dialogueLines > target.dialogueLines.upperBound {
            issues.append("整集对白过密：建议不超过 \(target.dialogueLines.upperBound) 句，实际 \(runtime.dialogueLines) 句")
            score -= 14
        }
        if runtime.spokenCharacters < target.spokenCharacters.lowerBound {
            issues.append("对白信息量不足：至少约 \(target.spokenCharacters.lowerBound) 个有效字，实际 \(runtime.spokenCharacters) 个")
            score -= 24
        } else if runtime.spokenCharacters > target.spokenCharacters.upperBound {
            issues.append("对白字数过多：建议不超过 \(target.spokenCharacters.upperBound) 个有效字，实际 \(runtime.spokenCharacters) 个")
            score -= 14
        }
        let lowerRuntime = Double(durationSeconds) * 0.82
        let upperRuntime = Double(durationSeconds) * 1.18
        if runtime.estimatedSeconds < lowerRuntime {
            issues.append("表演估时偏短：约 \(runtime.estimatedSeconds) 秒，目标 \(durationSeconds) 秒")
            score -= 18
        } else if runtime.estimatedSeconds > upperRuntime {
            issues.append("表演估时偏长：约 \(runtime.estimatedSeconds) 秒，目标 \(durationSeconds) 秒")
            score -= 18
        }
        let speakers = Set(scenes.flatMap(\.dialogue).map(\.speaker).filter { !$0.isEmpty })
        if speakers.count > target.maxSpeakingCharacters {
            issues.append("主要说话人物过多：建议不超过 \(target.maxSpeakingCharacters) 人，实际 \(speakers.count) 人")
            score -= 10
        }
        if runtime.longDialogueLines > max(1, runtime.dialogueLines / 5) {
            issues.append("长台词过多，建议拆成攻守更明确的短句")
            score -= 10
        }
        if scenes.contains(where: { readableCharacters($0.action) < 18 }) {
            issues.append("存在动作信息不足的场次，演员和镜头缺少表演抓手")
            score -= 12
        }

        let bounded = max(0, min(100, score))
        return EpisodeCompleteness(
            score: bounded,
            passed: bounded >= 78 && !issues.contains(where: { $0.contains("不足") }),
            issues: issues,
            runtime: runtime
        )
    }

    private static func punctuationPause(_ value: String) -> Double {
        let strong = value.filter { "。！？!?…".contains($0) }.count
        let weak = value.filter { "，、；：,;:".contains($0) }.count
        return Double(strong) * 0.22 + Double(weak) * 0.1
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
