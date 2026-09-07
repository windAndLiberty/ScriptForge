import Foundation

enum QualityEvaluator {
    static func evaluate(
        episodes: [Episode],
        characters: [CharacterProfile],
        options: AdaptationOptions,
        semanticIssues: [QualityGateIssue] = [],
        repairAttempts: Int = 0,
        acceptedRepairs: Int = 0,
        auditedWindows: Int = 0,
        outputLanguage: AppLanguage = .chinese
    ) -> QualityReport {
        let allContent = episodes.map(\.content).joined(separator: "\n")
        let leakedNames = characters.filter {
            $0.sourceName != $0.targetName && allContent.contains($0.sourceName)
        }
        let genericNames = characters.filter { CharacterExtractor.isGenericName($0.targetName) }
        let episodeAssessments = episodes.map {
            EpisodeBudget.assess(
                scenes: $0.scenes,
                durationSeconds: options.durationSeconds,
                language: outputLanguage
            )
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
                evidence: localized(
                    "成稿残留原名：\(leakedNames.map(\.sourceName).joined(separator: "、"))",
                    "The draft still contains source names: \(leakedNames.map(\.sourceName).joined(separator: ", "))",
                    outputLanguage
                ),
                repair: "Replace every source name according to the locked character mapping, then verify forms of address and dialogue speakers."
            ))
        }
        if !genericNames.isEmpty {
            deterministicIssues.append(issue(
                severity: .blocker,
                category: .character,
                episodes: episodes.map(\.number),
                evidence: localized(
                    "发现占位人物名：\(genericNames.map(\.targetName).joined(separator: "、"))",
                    "Placeholder character names were found: \(genericNames.map(\.targetName).joined(separator: ", "))",
                    outputLanguage
                ),
                repair: outputLanguage == .english
                    ? "Generate a natural, unique English-language name for every character."
                    : "Generate a natural, unique Chinese name for every character."
            ))
        }
        for (episode, assessment) in incompleteEpisodes {
            deterministicIssues.append(issue(
                severity: assessment.score < 55 ? .blocker : .major,
                category: .pacing,
                episodes: [episode.number],
                evidence: assessment.issues.joined(separator: outputLanguage == .english ? "; " : "；"),
                repair: "Preserve the episode's central conflict while expanding or compressing action and dialogue to fit a \(options.durationSeconds)-second performance budget."
            ))
        }
        for episode in missingHooks {
            deterministicIssues.append(issue(
                severity: .major,
                category: .hook,
                episodes: [episode.number],
                evidence: localized("本集缺少可执行开场钩子或结尾卡点。", "The episode lacks a playable opening hook or cliffhanger.", outputLanguage),
                repair: "Add a visible conflict within the first five seconds and end on an unfinished action, discovery, or choice."
            ))
        }
        for pair in duplicateConflicts {
            deterministicIssues.append(issue(
                severity: .major,
                category: .continuity,
                episodes: pair,
                evidence: localized("相邻分集的核心冲突高度重复，剧情没有形成新后果。", "Adjacent episodes repeat the same central conflict without creating a new consequence.", outputLanguage),
                repair: "Merge repeated material so the later episode adds a new fact, choice, or irreversible consequence."
            ))
        }
        if !riskyPatterns.isEmpty {
            deterministicIssues.append(issue(
                severity: .major,
                category: .compliance,
                episodes: episodes.map(\.number),
                evidence: localized("命中高风险表达：\(riskyPatterns.joined(separator: "、"))", "Potentially high-risk expressions were detected.", outputLanguage),
                repair: "Send the material for human compliance review and remove unnecessary actionable details that could enable harm."
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
                label: localized("人物改名一致性", "Character Naming Consistency", outputLanguage),
                score: leakedNames.isEmpty && genericNames.isEmpty ? 100 : 20,
                detail: leakedNames.isEmpty && genericNames.isEmpty
                    ? localized("已检查 \(characters.count) 组人物映射，未发现旧名或占位名", "Checked \(characters.count) character mappings; no source or placeholder names remain", outputLanguage)
                    : localized("人物命名存在阻断问题", "Character naming has a blocking issue", outputLanguage)
            ),
            metric(
                id: "runtime",
                label: localized("单集表演时长", "Episode Runtime", outputLanguage),
                score: deterministicScore,
                detail: localized("\(episodes.count - incompleteEpisodes.count)/\(episodes.count) 集达到完整成稿线", "\(episodes.count - incompleteEpisodes.count)/\(episodes.count) episodes meet the completeness threshold", outputLanguage)
            ),
            metric(
                id: "continuity",
                label: localized("跨集连续性", "Cross-Episode Continuity", outputLanguage),
                score: max(0, 100 - duplicateConflicts.count * 24),
                detail: duplicateConflicts.isEmpty
                    ? localized("未发现相邻集重复冲突", "No repeated conflict was found in adjacent episodes", outputLanguage)
                    : localized("发现 \(duplicateConflicts.count) 组重复推进", "Found \(duplicateConflicts.count) repeated progression pattern(s)", outputLanguage)
            ),
            metric(
                id: "hooks",
                label: localized("开场与结尾钩子", "Opening and Closing Hooks", outputLanguage),
                score: max(0, 100 - missingHooks.count * 20),
                detail: missingHooks.isEmpty
                    ? localized("每集均有开场钩子和结尾卡点", "Every episode has an opening hook and cliffhanger", outputLanguage)
                    : localized("\(missingHooks.count) 集钩子不完整", "\(missingHooks.count) episode(s) have incomplete hooks", outputLanguage)
            ),
            metric(
                id: "semantic",
                label: localized("独立语义终审", "Independent Semantic Review", outputLanguage),
                score: max(0, 100 - semanticIssues.filter { !$0.resolved }.count * 14),
                detail: auditedWindows > 0
                    ? localized("已审片 \(auditedWindows) 个重叠窗口", "Reviewed \(auditedWindows) overlapping episode window(s)", outputLanguage)
                    : localized("离线模式仅执行程序门禁", "Offline mode runs deterministic checks only", outputLanguage)
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
                    detail: localized("程序复算发现 \(deterministicIssues.count) 条问题", "Deterministic checks found \(deterministicIssues.count) issue(s)", outputLanguage)
                ),
                QualityGateTrace(
                    id: UUID().uuidString,
                    stage: "delivery_gate",
                    status: openMajor.isEmpty ? "passed" : "failed",
                    episodeNumbers: episodes.map(\.number),
                    detail: openMajor.isEmpty
                        ? localized("不存在开放的重大问题", "No open major issues remain", outputLanguage)
                        : localized("仍有 \(openMajor.count) 条重大问题", "\(openMajor.count) major issue(s) remain open", outputLanguage)
                ),
            ]
        )
        return QualityReport(
            score: score,
            metrics: metrics,
            warnings: [localized(
                "AI辅助内容须由编剧、制片和合规人员复核后再拍摄或发布。",
                "AI-assisted content must be reviewed by writing, production, and compliance professionals before filming or release.",
                outputLanguage
            )],
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

    private static func localized(
        _ chinese: String,
        _ english: String,
        _ language: AppLanguage
    ) -> String {
        language == .english ? english : chinese
    }
}
