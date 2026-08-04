import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Hashable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var label: String { self == .chinese ? "中文" : "English" }
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
        language == .english ? Self.english[key] ?? key : key
    }

    func text(_ key: String, _ values: [String: CustomStringConvertible]) -> String {
        values.reduce(text(key)) { output, entry in
            output.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value.description)
        }
    }

    private static let english: [String: String] = [
        "剧擎": "ScriptForge",
        "一键拆书": "Book Analysis",
        "改编工坊": "Adaptation Studio",
        "项目档案": "Projects",
        "提示词资产": "Prompt Assets",
        "当前项目": "CURRENT PROJECT",
        "尚未导入": "Nothing imported",
        "导入小说": "Import Novel",
        "导出成稿": "Export Script",
        "导出报告": "Export Report",
        "重置": "Reset",
        "新建项目": "New Project",
        "模型设置": "Model Settings",
        "本地优先": "Local first",
        "数据保存在此 Mac": "Data stays on this Mac",
        "把长篇故事，锻造成能拍的短剧。": "Forge long-form stories into shootable micro dramas.",
        "先建立证据和故事圣经，再规划、成稿、终审与定向修复。": "Build evidence and a story bible before planning, drafting, auditing, and targeted repair.",
        "支持 UTF-8 TXT，可拖入窗口": "Supports UTF-8 TXT and drag-and-drop",
        "原著章节": "Source Chapters",
        "人物新名": "Character Names",
        "改编规格": "Adaptation Brief",
        "目标集数": "Episode Count",
        "单集时长": "Runtime",
        "场次数由模型动态决定": "Scene count is decided dynamically by the model",
        "题材": "Genre",
        "基调": "Tone",
        "创作策略": "Creative Strategy",
        "精品爽剧": "Premium Hook Drama",
        "现实共鸣": "Grounded Resonance",
        "轻喜反转": "Light Comedy",
        "开始改编": "Start Adaptation",
        "重新生成": "Regenerate",
        "取消任务": "Cancel Task",
        "双模型可信管线": "Trusted Dual-Model Pipeline",
        "本地基础管线": "Local Baseline Pipeline",
        "人物命名中…": "Naming characters…",
        "分集设计": "Episode Map",
        "故事圣经": "Story Bible",
        "剧本编辑": "Script Editor",
        "质检报告": "Quality Report",
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
        "已生成集数": "Generated Episodes",
        "最近最多保留50个，超出后自动归档；归档项目不会自动删除。": "The 50 most recent projects are kept active. Older projects are archived and never auto-deleted.",
        "打开": "Open",
        "创建副本": "Duplicate",
        "归档": "Archive",
        "恢复": "Restore",
        "永久删除": "Delete Permanently",
        "没有项目": "No projects",
        "影响范围": "Influence",
        "恢复默认": "Restore Default",
        "保存提示词": "Save Prompt",
        "模型与安全设置": "Model & Security Settings",
        "启用在线双模型管线": "Enable online dual-model pipeline",
        "API Base URL": "API Base URL",
        "创作模型（Pro）": "Creative Model (Pro)",
        "高速模型（Flash）": "Fast Model (Flash)",
        "推理强度": "Reasoning Effort",
        "API Key": "API Key",
        "同意发送到当前端点": "Allow sending content to this endpoint",
        "在线改编会把所选小说片段发送到上方域名。密钥仅保存在 macOS Keychain。": "Online adaptation sends selected novel excerpts to the host above. The API key is stored only in macOS Keychain.",
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
        "语言": "Language",
    ]
}
