import Foundation

enum QualityEvaluator {
    static func evaluate(
        episodes: [Episode],
        characters: [CharacterProfile],
        options: AdaptationOptions,
        semanticIssues: [QualityGateIssue] = [],
        repairAttempts: Int = 0,
        acceptedRepairs: Int = 0,
        auditedWindows: Int = 0
    ) -> QualityReport {
        let allContent = episodes.map(\.content).joined(separator: "\n")
        let leakedNames = characters.filter {
            $0.sourceName != $0.targetName && allContent.contains($0.sourceName)
        }
        let genericNames = characters.filter { CharacterExtractor.isGenericName($0.targetName) }
        let episodeAssessments = episodes.map {
            EpisodeBudget.assess(scenes: $0.scenes, durationSeconds: options.durationSeconds)
        }
        let incompleteEpisodes = zip(episodes, episodeAssessments).filter { !$0.1.passed }
        let missingHooks = episodes.filter {
            $0.openingHook.trimmingCharacters(in: .whitespaces).isEmpty
                || $0.endHook.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let duplicateConflicts = adjacentDuplicateConflicts(episodes)
        let riskyPatterns = ["详细犯罪方法", "未成年人裸", "地域歧视", "美化赌博"]
            .filter(allContent.contains)

        var deterministicIssues: [QualityGateIssue] = []
        if !leakedNames.isEmpty {
            deterministicIssues.append(issue(
                severity: .blocker,
                category: .character,
                episodes: episodes.map(\.number),
                evidence: "成稿残留原名：\(leakedNames.map(\.sourceName).joined(separator: "、"))",
                repair: "按锁定人物映射替换所有旧名，并复查称谓和对白说话人。"
            ))
        }
        if !genericNames.isEmpty {
            deterministicIssues.append(issue(
                severity: .blocker,
                category: .character,
                episodes: episodes.map(\.number),
                evidence: "发现占位人物名：\(genericNames.map(\.targetName).joined(separator: "、"))",
                repair: "为人物生成自然且唯一的中文姓名。"
            ))
        }
        for (episode, assessment) in incompleteEpisodes {
            deterministicIssues.append(issue(
                severity: assessment.score < 55 ? .blocker : .major,
                category: .pacing,
                episodes: [episode.number],
                evidence: assessment.issues.joined(separator: "；"),
                repair: "保持本集核心冲突，按 \(options.durationSeconds) 秒表演预算补足或压缩动作与对白。"
            ))
        }
        for episode in missingHooks {
            deterministicIssues.append(issue(
                severity: .major,
                category: .hook,
                episodes: [episode.number],
                evidence: "本集缺少可执行开场钩子或结尾卡点。",
                repair: "在前5秒增加可见冲突，并把结尾停在未完成动作、发现或选择上。"
            ))
        }
        for pair in duplicateConflicts {
            deterministicIssues.append(issue(
                severity: .major,
                category: .continuity,
                episodes: pair,
                evidence: "相邻分集的核心冲突高度重复，剧情没有形成新后果。",
                repair: "合并重复表达，让后一集新增事实、选择或不可逆后果。"
            ))
        }
        if !riskyPatterns.isEmpty {
            deterministicIssues.append(issue(
                severity: .major,
                category: .compliance,
                episodes: episodes.map(\.number),
                evidence: "命中高风险表达：\(riskyPatterns.joined(separator: "、"))",
                repair: "交由人工合规复核，并删除不必要的可执行危险细节。"
            ))
        }

        let allIssues = mergeIssues(deterministicIssues + semanticIssues)
        let openMajor = allIssues.filter {
            !$0.resolved && ($0.severity == .blocker || $0.severity == .major)
        }
        let deterministicScore = episodeAssessments.isEmpty
            ? 0
            : episodeAssessments.map(\.score).reduce(0, +) / episodeAssessments.count
        let metrics = [
            metric(
                id: "rename",
                label: "人物改名一致性",
                score: leakedNames.isEmpty && genericNames.isEmpty ? 100 : 20,
                detail: leakedNames.isEmpty && genericNames.isEmpty
                    ? "已检查 \(characters.count) 组人物映射，未发现旧名或占位名"
                    : "人物命名存在阻断问题"
            ),
            metric(
                id: "runtime",
                label: "60秒表演时长",
                score: deterministicScore,
                detail: "\(episodes.count - incompleteEpisodes.count)/\(episodes.count) 集达到完整成稿线"
            ),
            metric(
                id: "continuity",
                label: "跨集连续性",
                score: max(0, 100 - duplicateConflicts.count * 24),
                detail: duplicateConflicts.isEmpty ? "未发现相邻集重复冲突" : "发现 \(duplicateConflicts.count) 组重复推进"
            ),
            metric(
                id: "hooks",
                label: "开场与结尾钩子",
                score: max(0, 100 - missingHooks.count * 20),
                detail: missingHooks.isEmpty ? "每集均有开场钩子和结尾卡点" : "\(missingHooks.count) 集钩子不完整"
            ),
            metric(
                id: "semantic",
                label: "独立语义终审",
                score: max(0, 100 - semanticIssues.filter { !$0.resolved }.count * 14),
                detail: auditedWindows > 0 ? "已审片 \(auditedWindows) 个重叠窗口" : "离线模式仅执行程序门禁"
            ),
        ]
        let score = metrics.map(\.score).reduce(0, +) / max(1, metrics.count)
        let gate = QualityGateReport(
            version: "trusted-quality-gate-v2",
            status: openMajor.isEmpty ? "passed" : "needs_review",
            deterministicScore: deterministicScore,
            auditedWindows: auditedWindows,
            repairAttempts: repairAttempts,
            acceptedRepairs: acceptedRepairs,
            issues: allIssues,
            trace: [
                QualityGateTrace(
                    id: UUID().uuidString,
                    stage: "deterministic_precheck",
                    status: deterministicIssues.isEmpty ? "passed" : "failed",
                    episodeNumbers: episodes.map(\.number),
                    detail: "程序复算发现 \(deterministicIssues.count) 条问题"
                ),
                QualityGateTrace(
                    id: UUID().uuidString,
                    stage: "delivery_gate",
                    status: openMajor.isEmpty ? "passed" : "failed",
                    episodeNumbers: episodes.map(\.number),
                    detail: openMajor.isEmpty ? "不存在开放的重大问题" : "仍有 \(openMajor.count) 条重大问题"
                ),
            ]
        )
        return QualityReport(
            score: score,
            metrics: metrics,
            warnings: ["AI辅助内容须由编剧、制片和合规人员复核后再拍摄或发布。"],
            passed: score >= 80 && openMajor.isEmpty,
            gate: gate
        )
    }

    private static func adjacentDuplicateConflicts(_ episodes: [Episode]) -> [[Int]] {
        guard episodes.count > 1 else { return [] }
        return (1..<episodes.count).compactMap { index in
            let previous = tokenSet(episodes[index - 1].contract.dominantConflict)
            let current = tokenSet(episodes[index].contract.dominantConflict)
            let overlap = Double(previous.intersection(current).count) / Double(max(1, min(previous.count, current.count)))
            return overlap >= 0.72 ? [episodes[index - 1].number, episodes[index].number] : nil
        }
    }

    private static func tokenSet(_ value: String) -> Set<String> {
        let characters = Array(value.filter { !$0.isWhitespace && !"，。！？；：,.!?;:".contains($0) })
        guard characters.count > 1 else { return Set([value]) }
        return Set((0..<(characters.count - 1)).map { String(characters[$0...$0 + 1]) })
    }

    private static func issue(
        severity: QualityIssueSeverity,
        category: QualityIssueCategory,
        episodes: [Int],
        evidence: String,
        repair: String
    ) -> QualityGateIssue {
        QualityGateIssue(
            id: UUID().uuidString,
            severity: severity,
            category: category,
            episodeNumbers: episodes,
            evidence: evidence,
            repairInstruction: repair,
            resolved: false
        )
    }

    private static func mergeIssues(_ issues: [QualityGateIssue]) -> [QualityGateIssue] {
        var seen = Set<String>()
        return issues.filter { issue in
            let key = "\(issue.category.rawValue)|\(issue.episodeNumbers)|\(issue.evidence)"
            return seen.insert(key).inserted
        }
    }

    private static func metric(id: String, label: String, score: Int, detail: String) -> QualityMetric {
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
