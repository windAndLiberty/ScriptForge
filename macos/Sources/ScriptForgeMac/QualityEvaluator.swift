import Foundation

enum QualityEvaluator {
    static func evaluate(
        episodes: [Episode],
        characters: [CharacterProfile],
        options: AdaptationOptions
    ) -> QualityReport {
        let allContent = episodes.map(\.content).joined(separator: "\n")
        let leaks = characters.filter {
            $0.sourceName != $0.targetName && allContent.contains($0.sourceName)
        }
        let sceneCount = episodes.reduce(0) { $0 + $1.scenes.count }
        let expectedScenes = max(1, episodes.count * options.scenesPerEpisode)
        let missingHooks = episodes.filter {
            $0.openingHook.isEmpty || $0.endHook.isEmpty
        }.count
        let dialogueCount = episodes.reduce(0) { total, episode in
            total + episode.scenes.reduce(0) { $0 + $1.dialogue.count }
        }
        let riskyWords = ["美化赌博", "详细犯罪方法", "未成年人裸", "地域歧视"]
        let risks = riskyWords.filter(allContent.contains)

        let metrics = [
            metric(
                id: "rename",
                label: "人物改名一致性",
                score: leaks.isEmpty ? 100 : max(20, 100 - leaks.count * 18),
                detail: leaks.isEmpty
                    ? "已检查 \(characters.count) 组人物映射，未发现旧名残留"
                    : "发现旧名残留：\(leaks.map(\.sourceName).joined(separator: "、"))"
            ),
            metric(
                id: "structure",
                label: "分集与场次结构",
                score: min(100, Int(Double(sceneCount) / Double(expectedScenes) * 100)),
                detail: "\(episodes.count) 集 / \(sceneCount) 场"
            ),
            metric(
                id: "hooks",
                label: "开场与结尾钩子",
                score: max(0, 100 - missingHooks * 15),
                detail: missingHooks == 0 ? "每集均有冷开场和结尾悬念" : "\(missingHooks) 集缺少钩子"
            ),
            metric(
                id: "dialogue",
                label: "对白可拍性",
                score: min(100, Int(Double(dialogueCount) / Double(max(1, episodes.count * 6)) * 100)),
                detail: "共 \(dialogueCount) 句对白"
            ),
            metric(
                id: "compliance",
                label: "内容风险初筛",
                score: risks.isEmpty ? 96 : 62,
                detail: risks.isEmpty ? "未命中内置高风险模式" : "命中 \(risks.count) 条风险表达"
            ),
        ]
        let score = metrics.map(\.score).reduce(0, +) / max(1, metrics.count)
        return QualityReport(
            score: score,
            metrics: metrics,
            warnings: [
                "AI 生成内容须人工复核；正式制作、备案和播出规则以主管部门及平台最新要求为准。"
            ],
            passed: score >= 80 && leaks.isEmpty
        )
    }

    private static func metric(
        id: String,
        label: String,
        score: Int,
        detail: String
    ) -> QualityMetric {
        let bounded = min(100, max(0, score))
        return QualityMetric(
            id: id,
            label: label,
            score: bounded,
            detail: detail,
            level: bounded >= 85 ? .good : bounded >= 65 ? .warning : .bad
        )
    }
}
