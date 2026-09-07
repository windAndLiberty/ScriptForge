import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var label: String { self == .chinese ? "中文" : "English" }
    var promptName: String { self == .chinese ? "Simplified Chinese" : "English" }

    static func detect(in value: String) -> AppLanguage {
        let scalars = value.unicodeScalars
        let hanCount = scalars.filter { scalar in
            (0x3400...0x4DBF).contains(Int(scalar.value))
                || (0x4E00...0x9FFF).contains(Int(scalar.value))
        }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(Int(scalar.value))
                || (0x0061...0x007A).contains(Int(scalar.value))
        }.count
        return hanCount > latinCount / 5 ? .chinese : .english
    }
}

struct LocalizedHint: Equatable, Sendable {
    let chinese: String
    let english: String

    func text(for language: AppLanguage) -> String {
        language == .english ? english : chinese
    }
}

@MainActor
final class LocalizationStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "uiLanguage") }
    }

    init() {
        language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? ""
        ) ?? .chinese
    }

    func text(_ key: String) -> String {
        Self.text(key, language: language)
    }

    nonisolated static func text(_ key: String, language: AppLanguage) -> String {
        if language == .english { return english[key] ?? key }
        return chineseByEnglish[key] ?? key
    }

    func projectName(_ value: String) -> String {
        Self.projectName(value, language: language)
    }

    func documentUnitTitle(_ value: String) -> String {
        Self.documentUnitTitle(value, language: language)
    }

    nonisolated static func documentUnitTitle(_ value: String, language: AppLanguage) -> String {
        if value == "正文" || value == "Main Text" {
            return language == .english ? "Main Text" : "正文"
        }
        let patterns: [(String, String)] = [
            (#"^第\s*(\d+)\s*章$"#, "Chapter $1"),
            (#"^第\s*(\d+)\s*集$"#, "Episode $1"),
        ]
        if language == .english {
            for (pattern, replacement) in patterns
            where value.range(of: pattern, options: .regularExpression) != nil {
                return value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            }
            if value.range(of: #"^第\s*(\d+)\s*卷$"#, options: .regularExpression) != nil {
                return value.replacingOccurrences(
                    of: #"^第\s*(\d+)\s*卷$"#,
                    with: "Volume $1",
                    options: .regularExpression
                )
            }
            if value.range(of: #"（片段\s*(\d+)）$"#, options: .regularExpression) != nil {
                return value.replacingOccurrences(
                    of: #"（片段\s*(\d+)）$"#,
                    with: " (Part $1)",
                    options: .regularExpression
                )
            }
            return value
        }
        let englishPatterns: [(String, String)] = [
            (#"^Chapter\s+(\d+)$"#, "第$1章"),
            (#"^Episode\s+(\d+)$"#, "第$1集"),
        ]
        for (pattern, replacement) in englishPatterns
        where value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        if value.range(of: #"^Volume\s+(\d+)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return value.replacingOccurrences(
                of: #"^Volume\s+(\d+)$"#,
                with: "第$1卷",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        if value.range(of: #"\s*\(Part\s+(\d+)\)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return value.replacingOccurrences(
                of: #"\s*\(Part\s+(\d+)\)$"#,
                with: "（片段$1）",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return value
    }

    nonisolated static func projectName(_ value: String, language: AppLanguage) -> String {
        let pairs = [
            (" · 短剧改编", " · Short Drama Adaptation"),
            ("·短剧改编", " · Short Drama Adaptation"),
            (" · 分镜项目", " · Storyboard Project"),
            ("·分镜项目", " · Storyboard Project"),
            (" · 创作项目", " · Authoring Project"),
            ("·创作项目", " · Authoring Project"),
            ("·创作工程", " · Authoring Workspace"),
            ("·分镜制作包", " · Storyboard Package"),
            (" · 副本", " · Copy"),
        ]
        var output = value
        for pair in pairs {
            if language == .english {
                output = output.replacingOccurrences(of: pair.0, with: pair.1)
            } else {
                output = output.replacingOccurrences(of: pair.1, with: pair.0)
            }
        }
        let exact = [
            "新建改编项目": "New Adaptation Project",
            "新建网文项目": "New Web Novel Project",
        ]
        if language == .english { return exact[output] ?? output }
        output = output
            .replacingOccurrences(of: " · 短剧改编", with: "·短剧改编")
            .replacingOccurrences(of: " · 分镜项目", with: "·分镜项目")
            .replacingOccurrences(of: " · 创作项目", with: "·创作项目")
        return exact.first(where: { $0.value == output })?.key ?? output
    }

    nonisolated static func errorText(_ message: String, language: AppLanguage) -> String {
        guard language == .english else { return message }
        if let exact = english[message] { return exact }
        if message.hasPrefix("模型 JSON 结构不完整：") {
            let detail = String(message.dropFirst("模型 JSON 结构不完整：".count))
            return "Model JSON is incomplete: \(englishJSONDetail(detail))"
        }
        let prefixes: [(String, String)] = [
            ("模型网络请求失败：", "Model network request failed: "),
            ("提示词缺少变量：", "Prompt variables are missing: "),
            ("Keychain 错误：", "Keychain error: "),
        ]
        for (source, replacement) in prefixes where message.hasPrefix(source) {
            return replacement + message.dropFirst(source.count)
        }
        if message.hasPrefix("模型请求失败（HTTP "),
           let closing = message.firstIndex(of: "）") {
            let status = message[message.index(message.startIndex, offsetBy: 12)..<closing]
            let detailStart = message.index(after: closing)
            let detail = message[detailStart...].drop(while: { $0 == "：" || $0 == " " })
            return "Model request failed (HTTP \(status)): \(detail)"
        }
        if message.hasPrefix("暂不支持 "),
           let separator = message.range(of: " 格式；支持 ") {
            let format = message[message.index(message.startIndex, offsetBy: 5)..<separator.lowerBound]
            let supported = DocumentImporter.supportedFormatNames.joined(separator: ", ")
            return "\(format) format is not supported. Supported formats: \(supported)"
        }
        if let separator = message.range(of: " 中没有可提取的文字；") {
            let format = message[..<separator.lowerBound]
            return "No extractable text was found in the \(format). Scanned PDFs must be processed with OCR first"
        }
        return message
    }

    nonisolated private static func englishJSONDetail(_ value: String) -> String {
        let replacements: [(String, String)] = [
            ("未返回可见正文；推理可能耗尽完成预算", "No visible content was returned; reasoning may have exhausted the completion budget"),
            ("响应 JSON 可能被截断；请缩小本次任务或单步重试", "The response JSON may be truncated. Reduce the task size or retry this step"),
            ("响应不是有效 JSON；请单步重试", "The response is not valid JSON. Retry this step"),
            ("响应不是 UTF-8 JSON", "The response is not UTF-8 JSON"),
            (" 数据损坏：", " contains invalid data: "),
            (" 类型错误：", " has the wrong type: "),
            (" 缺少值", " has no value"),
            (" 缺失", " is missing"),
        ]
        return replacements.reduce(value) { result, pair in
            result.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    func text(_ key: String, _ values: [String: CustomStringConvertible]) -> String {
        values.reduce(text(key)) { output, entry in
            output.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value.description)
        }
    }

    func countedUnit(_ key: String, count: Int) -> String {
        guard language == .english else { return key }
        switch key {
        case "章", "章节": return count == 1 ? "chapter" : "chapters"
        case "集", "分集": return count == 1 ? "episode" : "episodes"
        case "场": return count == 1 ? "scene" : "scenes"
        default: return text(key)
        }
    }

    func text(_ diagnostic: SourceDiagnostic) -> String {
        guard language == .english else { return diagnostic.message }
        let numbers = diagnostic.unitNumbers.map(String.init).joined(separator: ", ")
        switch diagnostic.code {
        case "screenplay.duplicate_episode_numbers":
            return "Duplicate episode numbers: \(numbers)."
        case "screenplay.missing_episode_numbers":
            return "Episode sequence gap; missing: \(numbers)."
        case "screenplay.episode_order":
            return "Some episode numbers are out of order. Review before storyboarding."
        case "screenplay.no_scene_headings":
            return "Episode structure was detected without scene headings; a safe one-scene fallback will be used."
        case "screenplay.unlabeled_blocks":
            return "No visual/dialogue block labels were found; parsing will use scene headings and speaker syntax."
        case "screenplay.single_unit":
            return "An unsegmented screenplay was detected and imported as a single source unit."
        case "source.episodic_prose":
            return "Episode headings were found without screenplay structure, so the source was imported as prose."
        case "source.empty_units":
            return "These source units have no body text: \(numbers)."
        default:
            return diagnostic.message
        }
    }

    nonisolated private static let english: [String: String] = [
        "剧擎": "ScriptForge",
        "一键拆书": "Book Analysis",
        "使用原文语言": "Use Source Language",
        "默认保持原稿的主要语言，避免分析与分集中英文混杂。": "Preserve the manuscript's dominant language by default to prevent mixed-language analysis and episodes.",
        "已检测原文语言": "Detected Source Language",
        "指定输出语言": "Output Language",
        "模式": "Mode",
        "改编工坊": "Adaptation Studio",
        "项目档案": "Projects",
        "提示词资产": "Prompt Assets",
        "当前项目": "CURRENT PROJECT",
        "尚未导入": "Nothing imported",
        "导入小说": "Import Novel",
        "导入故事或剧本": "Import Story or Script",
        "导出成稿": "Export Script",
        "导出报告": "Export Report",
        "重置": "Reset",
        "新建项目": "New Project",
        "模型设置": "Model Settings",
        "界面语言": "Interface Language",
        "主题": "Theme",
        "无障碍访问": "Accessibility",
        "界面缩放": "Interface Scale",
        "放大": "Zoom In",
        "缩小": "Zoom Out",
        "实际大小": "Actual Size",
        "重置缩放": "Reset Zoom",
        "缩放级别": "Zoom Level",
        "视图": "View",
        "跟随系统": "System",
        "浅色": "Light",
        "深色": "Dark",
        "本地优先": "Local first",
        "数据保存在此 Mac": "Data stays on this Mac",
        "把长篇故事，锻造成能拍的短剧。": "Forge long-form stories into shootable micro dramas.",
        "先建立证据和故事圣经，再规划、成稿、终审与定向修复。": "Build evidence and a story bible before planning, drafting, auditing, and targeted repair.",
        "支持 UTF-8 TXT，可拖入窗口": "Supports UTF-8 TXT and drag-and-drop",
        "从故事到已有剧本，锻造成能拍的短剧。": "Forge stories and existing scripts into shootable micro dramas.",
        "自动识别小说或剧本；已有剧本保留集场结构，直接进入分镜。": "Automatically detect prose or screenplay; preserve existing episode and scene structure for storyboarding.",
        "本地支持 DOCX、TXT 与 Markdown": "Local DOCX, TXT, and Markdown support",
        "本地支持 {{formats}}": "Local support for {{formats}}",
        "也可以将文件拖到窗口任意位置": "Or drag a file anywhere into the window",
        "拖拽导入": "Drag to Import",
        "松开以导入到创作工坊": "Drop to import into Author Studio",
        "松开以导入到改编工坊": "Drop to import into Adaptation Studio",
        "支持 DOCX、TXT 与 Markdown；一次导入一个文件": "DOCX, TXT, and Markdown; import one file at a time",
        "支持 {{formats}}；一次导入一个文件": "Supports {{formats}}; import one file at a time",
        "原著章节": "Source Chapters",
        "剧本分集": "Script Episodes",
        "小说 / 故事": "Novel / Story",
        "已有剧本": "Existing Script",
        "集": "episodes",
        "章": "chapters",
        "有效字符": "characters",
        "人物新名": "Character Names",
        "原稿人物": "Original Cast",
        "改编规格": "Adaptation Brief",
        "目标集数": "Episode Count",
        "原稿集数": "Original Episodes",
        "单集时长": "Runtime",
        "场次数由模型动态决定": "Scene count is decided dynamically by the model",
        "场次数与内容来自原稿结构": "Scene count and content come from the original script",
        "已有剧本不会被二次改编；集、场、对白和钩子按原稿保留。": "Existing scripts are not re-adapted; episodes, scenes, dialogue, and hooks are preserved.",
        "题材": "Genre",
        "基调": "Tone",
        "玄幻逆袭": "Fantasy Comeback",
        "高燃、克制、强反转": "High-energy, restrained, with strong reversals",
        "正文": "Main Text",
        "核心主角": "Core Protagonist",
        "主要角色": "Main Character",
        "关键配角": "Key Supporting Character",
        "本地生成": "Generated Locally",
        "模型生成": "Generated by Model",
        "手动编辑": "Edited Manually",
        "阻断": "Blocker",
        "严重": "Major",
        "轻微": "Minor",
        "管线就绪": "Pipeline ready",
        "提示词快照": "Prompt Snapshot",
        "创作策略": "Creative Strategy",
        "精品爽剧": "Premium Hook Drama",
        "现实共鸣": "Grounded Resonance",
        "轻喜反转": "Light Comedy",
        "开始改编": "Start Adaptation",
        "重新生成": "Regenerate",
        "重新解析原稿": "Re-parse Original",
        "取消任务": "Cancel Task",
        "双模型可信管线": "Trusted Dual-Model Pipeline",
        "本地基础管线": "Local Baseline Pipeline",
        "本地剧本直通": "Local Script Pass-through",
        "人物命名中…": "Naming characters…",
        "分集设计": "Episode Map",
        "故事圣经": "Story Bible",
        "剧本编辑": "Script Editor",
        "质检报告": "Quality Report",
        "分镜制作": "Storyboard",
        "分镜制作包": "Storyboard Production Package",
        "从已批准剧本生成镜头、首帧提示词、声音和连续性标注": "Turn the approved script into shots, keyframe prompts, sound, and continuity notes",
        "生成分镜": "Generate Storyboard",
        "重新生成分镜": "Regenerate Storyboard",
        "导出分镜": "Export Storyboard",
        "尚未生成分镜": "No storyboard generated",
        "离线模式也可生成完整文本分镜；图片与配音按需使用 BYOK 模型。": "Offline mode can generate the full text storyboard. Images and voice use optional BYOK models.",
        "生成首帧": "Generate Keyframe",
        "重新生成首帧": "Regenerate Keyframe",
        "生成配音": "Generate Voice",
        "重新生成配音": "Regenerate Voice",
        "播放": "Play",
        "画面动作": "Visual Action",
        "台词": "Dialogue",
        "旁白": "Narration",
        "构图": "Composition",
        "声音设计": "Sound Design",
        "连续性": "Continuity",
        "制作备注": "Production Notes",
        "首帧提示词": "Keyframe Prompt",
        "反向提示词": "Negative Prompt",
        "首帧待生成": "Keyframe pending",
        "冷开场": "Opening Hook",
        "本集目标": "Objective",
        "中段反转": "Reversal",
        "结尾卡点": "End Hook",
        "动态场次": "Dynamic Scenes",
        "尚未生成剧本": "No script generated",
        "综合分": "Overall",
        "达到交付线": "Passed delivery gate",
        "需要人工复核": "Needs human review",
        "开放问题": "Open Issues",
        "最近项目": "Recent",
        "已归档": "Archived",
        "累计章节": "Total Chapters",
        "累计内容单元": "Total Source Units",
        "已生成集数": "Generated Episodes",
        "最近最多保留50个，超出后自动归档；归档项目不会自动删除。": "The 50 most recent projects are kept active. Older projects are archived and never auto-deleted.",
        "打开": "Open",
        "创建副本": "Duplicate",
        "归档": "Archive",
        "恢复": "Restore",
        "永久删除": "Delete Permanently",
        "没有项目": "No projects",
        "影响范围": "Influence",
        "故事证据提取": "Story Evidence Extraction",
        "章节分析与拆书分析的证据层": "Chapter analysis and the evidence layer for Book Analysis",
        "控制从原稿保留哪些人物、事件、因果关系和伏笔；不直接决定剧本风格。": "Controls which characters, events, causal links, and foreshadowing elements are retained from the source; it does not directly set screenplay style.",
        "轻量人物改名": "Lightweight Character Renaming",
        "导入后的高速模型命名调用": "Flash-model naming call after import",
        "控制新的剧本人物名称；手动编辑的名称优先级最高，后续模型调用不得更改。": "Controls new screenplay character names. Manually edited names have the highest priority and must not be changed by later model calls.",
        "故事圣经与连续性": "Story Bible and Continuity",
        "全剧事实、人物关系、时间线与道具连续性": "Series facts, relationships, timeline, and prop continuity",
        "约束各集的人物身份、关系、能力规则、地点变化和伏笔回收；是连续性判断的权威依据。": "Constrains character identity, relationships, ability rules, location changes, and foreshadowing payoffs across all episodes; it is the canonical source for continuity decisions.",
        "中文竖屏短剧分集规划": "Chinese Vertical-Drama Episode Planning",
        "全剧分集契约与每集场景建议": "Series-wide episode contracts and per-episode scene recommendations",
        "控制每集的新事件、开场钩子、反转、结尾悬念和动态场次数；不负责撰写完整对白。": "Controls each episode's new event, opening hook, reversal, closing cliffhanger, and dynamic scene count; it does not draft complete dialogue.",
        "可拍摄的分集初稿": "Shootable Episode Draft",
        "每集场景动作与对白": "Per-episode scene action and dialogue",
        "直接控制最终剧本的节奏、可见动作、对白密度和结尾悬念。": "Directly controls pacing, visible action, dialogue density, and the closing cliffhanger in the final screenplay.",
        "基于证据的质量门禁": "Evidence-Grounded Quality Gate",
        "分集复核、全剧审计、问题台账与定向修复": "Episode review, series audit, issue ledger, and targeted repair",
        "决定草稿是否通过并定位修复点；不得只为提高分数而改写有效内容。": "Determines whether a draft passes and identifies repair locations; it must not rewrite valid content merely to increase a score.",
        "分镜与多媒体制作包": "Storyboard and Multimedia Production Package",
        "从已批准剧本生成镜头、关键帧、声音与连续性备注": "Approved screenplay to shots, keyframes, sound, and continuity notes",
        "控制镜头拆分、构图、运镜、声音设计和图像提示词，但不改变已批准的故事。": "Controls shot breakdown, composition, camera movement, sound design, and image prompts without changing the approved story.",
        "六部分拆书分析": "Six-Section Book Analysis",
        "结构、人物、商业爽点、文风、技法与改编建议": "Structure, characters, commercial payoffs, style, techniques, and adaptation guidance",
        "控制分析报告的深度与证据标准；不直接修改剧本草稿。": "Controls the depth and evidence standard of the analysis report; it does not directly modify the screenplay draft.",
        "恢复默认": "Restore Default",
        "保存提示词": "Save Prompt",
        "模型与安全设置": "Model & Security Settings",
        "启用在线双模型管线": "Enable online dual-model pipeline",
        "API Base URL": "API Base URL",
        "创作模型（Pro）": "Creative Model (Pro)",
        "高速模型（Flash）": "Fast Model (Flash)",
        "图片模型（可选）": "Image Model (Optional)",
        "语音模型（可选）": "Speech Model (Optional)",
        "配音音色": "Voice",
        "推理强度": "Reasoning Effort",
        "API Key": "API Key",
        "同意发送到当前端点": "Allow sending content to this endpoint",
        "在线改编与可选多媒体生成只发送到上方域名。图片和语音模型留空即禁用；密钥仅保存在 macOS Keychain。": "Online adaptation and optional media generation only send data to the host above. Leave image and speech models blank to disable them. The API key stays in macOS Keychain.",
        "保存连接": "Save Connection",
        "取消": "Cancel",
        "准备开始一键拆书": "Ready for book analysis",
        "开始一键拆书": "Start Book Analysis",
        "重新一键拆书": "Run Again",
        "拆书报告": "Book Analysis Report",
        "修订指令": "Revision instruction",
        "提交微调": "Revise Report",
        "证据覆盖": "Evidence Coverage",
        "永久删除项目": "Delete Project Permanently",
        "此操作不可撤销。项目文件和全部生成资产都会被删除。": "This cannot be undone. The project and all generated assets will be deleted.",
        "确认删除": "Delete",
        "创作工坊": "Author Studio",
        "创作工作流": "Author Workflows",
        "改编与分镜": "Adaptation & Storyboard",
        "从灵感到连载成稿": "From Idea to Serialized Draft",
        "六条固定工作流、作者确认点、章节版本和本地资料库。": "Six focused workflows, author approvals, chapter versions, and a local story database.",
        "新建网文项目": "New Web Novel Project",
        "导入已有原稿": "Import Existing Manuscript",
        "未配置模型时仍可编辑、检查和导出；生成步骤会等待 BYOK 模型。": "Editing, checks, and export remain available without a model; generation waits for your BYOK model.",
        "工作流模板": "WORKFLOW TEMPLATES",
        "新书孵化": "Book Incubation",
        "把灵感整理成题材、卖点、主角与长期冲突明确的新书企划。": "Turn an idea into an actionable concept with genre, hooks, protagonist, and long-term conflict.",
        "建立人物、规则、地点、势力、物品与文风的长期事实库。": "Build a durable source of truth for characters, rules, places, factions, items, and style.",
        "从长期剧情弧拆出卷纲、章节目标、冲突、信息增量和钩子。": "Break the long arc into volumes, chapter goals, conflicts, reveals, and hooks.",
        "章节生产": "Chapter Production",
        "批量确认章卡后逐章生成正文，并在每章成稿处停下。": "Approve chapter cards as a batch, then draft and review one chapter at a time.",
        "连贯性审计": "Continuity Audit",
        "检查人物状态、知情范围、时间、地点、能力、物品和伏笔。": "Audit character state, knowledge, time, location, abilities, items, and setups.",
        "章节精修": "Chapter Polish",
        "在不改变剧情事实的前提下精修节奏、对白、视角和表达。": "Polish pacing, dialogue, viewpoint, and prose without changing story facts.",
        "灵感或题材": "Idea or Genre",
        "规划章节": "Planned Chapters",
        "本批章节": "Batch Chapters",
        "本次运行补充": "Run Instructions",
        "可选步骤与上下文": "Optional Steps & Context",
        "项目级创作规则": "Project Writing Rules",
        "预览最终提示词": "Preview Final Prompt",
        "开始运行": "Start Run",
        "当前运行": "Current Run",
        "运行历史": "Run History",
        "排队": "Queued",
        "运行中": "Running",
        "等待模型": "Waiting for Model",
        "等待确认": "Waiting for Approval",
        "已中断": "Interrupted",
        "失败": "Failed",
        "完成": "Completed",
        "已取消": "Cancelled",
        "当前": "Current",
        "接受并继续": "Accept & Continue",
        "停止工作流": "Stop Workflow",
        "继续 / 重试": "Continue / Retry",
        "章节": "Chapters",
        "待确认": "Review",
        "对比": "Compare",
        "拒绝": "Reject",
        "保存版本": "Save Version",
        "当前正式版": "Current Version",
        "候选稿": "Candidate",
        "版本": "Versions",
        "版本历史": "Version History",
        "恢复会创建新版本，不覆盖历史": "Restore creates a new version and preserves history",
        "字": "characters",
        "创作资料库": "Story Workspace",
        "新书企划": "Creative Brief",
        "尚未生成": "Not generated",
        "张卡片": "cards",
        "卷章规划": "Volume & Chapter Outline",
        "卷": "volumes",
        "连续性问题": "Continuity Issues",
        "导出": "Export",
        "移交到改编工坊": "Send to Adaptation Studio",
        "创建快照并移交": "Create Snapshot & Send",
        "将全部已接受章节编译为不可变快照；现有改编和分镜结果会失效，创作版本仍可恢复。": "Compile all accepted chapters into an immutable snapshot. Existing adaptation and storyboard results will be invalidated; authoring versions remain restorable.",
        "工作流级提示词；项目规则和本次补充会在运行时追加。": "Workflow prompt; project rules and run instructions are appended at runtime.",
        "整理创作目标": "Prepare Creative Goal",
        "生成新书企划": "Generate Creative Brief",
        "确认企划": "Approve Brief",
        "选择相关资料": "Select Context",
        "构建故事圣经": "Build Story Bible",
        "检查重复与空卡": "Check Duplicates & Empty Cards",
        "确认故事圣经": "Approve Story Bible",
        "整理企划与设定": "Prepare Brief & Bible",
        "生成卷章规划": "Generate Volume & Chapter Outline",
        "检查章号、推进与钩子": "Check Numbering, Progression & Hooks",
        "确认卷章规划": "Approve Outline",
        "选择相关上下文": "Select Relevant Context",
        "生成本批章卡": "Generate Chapter Cards",
        "确认本批章卡": "Approve Chapter Cards",
        "逐章生成正文": "Draft Chapters",
        "检查连续性与完整性": "Check Continuity & Completeness",
        "逐章确认成稿": "Review Chapter Drafts",
        "收集事实与章节": "Collect Facts & Chapters",
        "执行连贯性审计": "Run Continuity Audit",
        "归并重复问题": "Merge Duplicate Issues",
        "确认问题台账": "Approve Issue Log",
        "读取当前正文与设定": "Load Draft & Story Facts",
        "生成精修候选稿": "Generate Polished Candidate",
        "检查事实漂移": "Check Fact Drift",
        "对比并确认": "Compare & Approve",
        "语言": "Language",
        "词": "words",
        "创作系统 / 拆书分析": "CREATION SYSTEM / BOOK ANALYSIS",
        "创作系统 / 作者工作流": "CREATION SYSTEM / AUTHOR WORKFLOWS",
        "创作系统 / 短剧改编": "CREATION SYSTEM / ADAPTATION",
        "本地工作区 / 项目": "LOCAL WORKSPACE / PROJECTS",
        "创作系统 / 提示词": "CREATION SYSTEM / PROMPTS",
        "名称": "Name",
        "向模型可见": "Visible to Model",
        "章节目标": "Chapter Objective",
        "冲突": "Conflict",
        "结尾钩子": "Closing Hook",
        "人物": "Characters",
        "世界规则": "World Rules",
        "地点": "Locations",
        "势力": "Factions",
        "物品": "Items",
        "能力": "Abilities",
        "文风": "Prose Style",
        "已规划": "planned",
        "planned": "Planned",
        "起草中": "drafting",
        "drafting": "Drafting",
        "审核中": "review",
        "review": "In Review",
        "已接受": "accepted",
        "accepted": "Accepted",
        "导入版本": "imported",
        "imported": "Imported",
        "生成版本": "generated",
        "generated": "Generated",
        "精修版本": "polished",
        "polished": "Polished",
        "手动版本": "manual",
        "manual": "Manual",
        "恢复版本": "restored",
        "restored": "Restored",
        "时间线": "Timeline",
        "场": "scenes",
        "就绪": "ready",
        "第 {{number}} 章": "Chapter {{number}}",
        "第 {{number}} 集": "Episode {{number}}",
        "{{count}} 章节": "{{count}} chapters",
        "{{chapters}} 章节 · {{episodes}} 分集": "{{chapters}} chapters · {{episodes}} episodes",
        "在线": "Online",
        "离线": "Offline",
        "导入原稿": "Imported Manuscript",
        "已批准的创作企划": "Approved Creative Brief",
        "相关故事圣经": "Relevant Story Bible",
        "当前卷章规划": "Current Volume and Chapter Outline",
        "活动伏笔": "Active Foreshadowing",
        "当前人物状态": "Current Character States",
        "例如 gpt-image-1": "e.g. gpt-image-1",
        "例如 gpt-4o-mini-tts": "e.g. gpt-4o-mini-tts",
        "请先导入故事或剧本": "Import a story or script first",
        "人物新名不能为空、重复、与原名相同或使用占位名": "Character names cannot be empty, duplicated, identical to source names, or placeholders",
        "在线模式需要先配置 API Key": "Configure an API key before using online mode",
        "尚未生成可导出的剧本": "No script is available to export",
        "尚未生成拆书报告": "No book analysis report has been generated",
        "尚未生成分镜制作包": "No storyboard package has been generated",
        "工作流不存在": "The workflow does not exist",
        "工作流没有可执行步骤": "The workflow has no executable step",
        "请先确认当前候选结果": "Approve or reject the current candidate first",
        "没有可确认的候选结果": "There is no candidate to approve",
        "请先选择章节": "Select a chapter first",
        "模型 Base URL 无效": "The model Base URL is invalid",
        "模型没有返回可读取的文本": "The model returned no readable text",
        "没有可导出的已接受章节": "There are no accepted chapters to export",
        "文件内容为空": "The file is empty",
        "无法按 UTF-8 读取文本": "The text could not be read as UTF-8",
        "一次只能导入一个文档": "Only one document can be imported at a time",
        "没有检测到可导入的文件": "No importable document was detected",
        "拖入内容不是本地文件": "The dropped item is not a local file",
        "拖入的文件不存在或已经移动": "The dropped file does not exist or has been moved",
        "暂不支持导入文件夹；RTFD 文档包除外": "Folders cannot be imported, except RTFD document packages",
        "无法读取文本编码；支持 UTF-8、UTF-16 与 GB18030": "The text encoding could not be read. UTF-8, UTF-16, and GB18030 are supported",
        "DOCX 文件结构无效或正文已损坏": "The DOCX structure is invalid or its content is damaged",
        "PDF 文件无效、已加密或正文已损坏": "The PDF is invalid, encrypted, or damaged",
        "富文本文档无效或正文已损坏": "The rich-text document is invalid or damaged",
        "文档超过本地安全解析上限": "The document exceeds the local safe parsing limit",
        "只有已归档项目可以永久删除": "Only archived projects can be permanently deleted",
        "项目不存在或已经被删除": "The project does not exist or has been deleted",
    ]

    nonisolated private static let chineseByEnglish: [String: String] = english.reduce(into: [:]) { result, entry in
        if result[entry.value] == nil { result[entry.value] = entry.key }
    }
}
