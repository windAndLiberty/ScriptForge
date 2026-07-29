import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
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
        let saved = UserDefaults.standard.string(forKey: "uiLanguage")
        language = AppLanguage(rawValue: saved ?? "") ?? .chinese
    }

    func text(_ key: String) -> String {
        guard language == .english else { return key }
        return Self.english[key] ?? key
    }

    func text(_ key: String, _ values: [String: CustomStringConvertible]) -> String {
        var result = text(key)
        for (name, value) in values {
            result = result.replacingOccurrences(of: "{{\(name)}}", with: value.description)
        }
        return result
    }

    func progressText(_ value: String) -> String {
        guard language == .english else { return value }
        if value.hasPrefix("正在分析 "), value.hasSuffix(" 章") {
            let range = value
                .replacingOccurrences(of: "正在分析 ", with: "")
                .replacingOccurrences(of: " 章", with: "")
            return "Analyzing chapters \(range)"
        }
        if value.hasPrefix("正在生成第 "), value.hasSuffix(" 集") {
            let range = value
                .replacingOccurrences(of: "正在生成第 ", with: "")
                .replacingOccurrences(of: " 集", with: "")
            return "Drafting episode \(range)"
        }
        if value.hasPrefix("已拆解 ") {
            return value
                .replacingOccurrences(of: "已拆解 ", with: "Parsed ")
                .replacingOccurrences(of: " 章并识别 ", with: " chapters and found ")
                .replacingOccurrences(of: " 位主要人物", with: " key characters")
        }
        if value.hasPrefix("已完成 ") {
            return value
                .replacingOccurrences(of: "已完成 ", with: "Completed ")
                .replacingOccurrences(of: " 集，质检 ", with: " episodes · QA ")
                .replacingOccurrences(of: " 分", with: "")
        }
        return text(value)
    }

    private static let english: [String: String] = [
        "剧擎": "ScriptForge",
        "改编工坊": "Adaptation Studio",
        "项目档案": "Projects",
        "当前项目": "CURRENT PROJECT",
        "尚未导入": "Nothing imported",
        "导入小说后开始": "Import a novel to begin",
        "模型与偏好": "Model & Preferences",
        "本地自动保存": "Local Autosave",
        "本地创作空间": "Local Workspace",
        "数据保存在此 Mac": "Data stays on this Mac",
        "本地已保存": "Saved locally",
        "导入小说": "Import Novel",
        "导出成稿": "Export Script",
        "结构化改编管线": "Structured Adaptation Pipeline",
        "人物表已就绪，确认改名后即可生成":
            "Character bible is ready. Confirm names to generate.",
        "文本拆解": "Ingest",
        "故事事实": "Story Facts",
        "人物改名": "Rename Cast",
        "分集规划": "Episode Plan",
        "逐集成稿": "Draft Episodes",
        "质量校验": "Quality Gate",
        "把长篇故事，锻造成能拍的短剧。":
            "Forge long-form stories into shootable micro dramas.",
        "不再把整本小说塞进一次提示词。先建立故事事实、人物圣经和改名表，再规划分集、逐集生成并自动质检。":
            "Build story facts, a character bible, and a rename map before planning, drafting, and validating every episode.",
        "导入小说文本": "Import Novel Text",
        "支持 UTF-8 TXT / MD，可直接拖入窗口":
            "Supports UTF-8 TXT / MD and drag-and-drop",
        "原著章节": "Source Chapters",
        "章节": "Chapters",
        "字符": "Characters",
        "已读取": "Loaded",
        "原文预览": "SOURCE PREVIEW",
        "改编规格": "Adaptation Brief",
        "目标集数": "Episode Count",
        "单集时长": "Episode Runtime",
        "每集场次": "Scenes per Episode",
        "创作策略": "Creative Strategy",
        "精品爽剧": "Premium Hook Drama",
        "现实共鸣": "Grounded Resonance",
        "轻喜反转": "Light Comedy & Reversals",
        "强钩子": "Strong Hooks",
        "高信息密度": "High Information Density",
        "可拍性优先": "Shootability First",
        "离线验收管线": "Offline Acceptance Pipeline",
        "结构化大模型管线": "Structured LLM Pipeline",
        "离线验收": "Offline",
        "在线精修": "Online Polish",
        "开始改编": "Start Adaptation",
        "重新生成": "Regenerate",
        "正在运行…": "Running…",
        "人物改名表已预填": "Rename map prefilled",
        "确认右侧角色新名与改编规格，系统将先规划全部分集，再逐集生成和校验。":
            "Confirm cast names and the brief. The app will plan every episode before drafting and validating each one.",
        "分集设计": "Episode Map",
        "剧本编辑": "Script Editor",
        "质检报告": "QA Report",
        "人物改名表": "Character Rename Map",
        "旧名仅用于源文匹配；成稿强制使用新名并检查残留。":
            "Original names are used only for source matching. Drafts enforce new names and scan for leaks.",
        "原著角色": "Source Character",
        "剧本新名": "Script Name",
        "交付质量": "Handoff Quality",
        "综合分": "Overall",
        "达到初稿交付线": "Draft meets the handoff bar",
        "需要修复后再交付": "Fix issues before handoff",
        "模型与安全设置": "Model & Security Settings",
        "API Key 安全保存在 macOS Keychain":
            "API key is stored securely in macOS Keychain",
        "模型": "Model",
        "推理强度": "Reasoning Effort",
        "保存连接": "Save Connection",
        "取消": "Cancel",
        "语言": "Language",
        "章节与场次": "Chapters & Scenes",
        "人物改名一致性": "Rename Consistency",
        "分集与场次结构": "Episode & Scene Structure",
        "开场与结尾钩子": "Opening & End Hooks",
        "对白可拍性": "Dialogue Shootability",
        "内容风险初筛": "Content Risk Screening",
        "生成失败": "Generation failed",
        "请先导入小说文本": "Import a novel first",
        "人物新名不能为空或重复": "New character names cannot be blank or duplicated",
        "在线模式需要先配置 API Key":
            "Online mode requires an API key in Model Settings",
        "{{chapters}} 章节 · {{characters}} 字符":
            "{{chapters}} chapters · {{characters}} characters",
        "集": "episodes",
        "秒": "sec",
        "场": "scenes",
        "题材": "Genre",
        "基调": "Tone",
        "生成模式": "Generation Mode",
        "全剧规划已生成": "Full Series Plan Generated",
        "第 {{number}} 集": "Episode {{number}}",
        "可直接编辑": "Editable",
        "尚未生成剧本": "No Script Yet",
        "完成改编后，可在这里逐集编辑、校对和导出。":
            "After generation, edit, proofread, and export each episode here.",
        "待处理项": "Action Items",
        "等待质量校验": "Waiting for Quality Check",
        "生成完成后会自动检查改名、结构、钩子、对白与内容风险。":
            "After generation, the app checks renames, structure, hooks, dialogue, and content risks.",
        "锁定改名": "Lock Rename",
        "启用在线结构化大模型管线":
            "Enable Structured Online LLM Pipeline",
        "已保存；留空则保持不变": "Saved; leave blank to keep unchanged",
        "核心主角": "Lead",
        "主要角色": "Main Character",
        "关键配角": "Supporting Character",
        "正在抽取故事事实、冲突和情绪爆点":
            "Extracting story facts, conflicts, and emotional peaks",
        "正在应用人物改名表并检查重名":
            "Applying the rename map and checking duplicates",
        "正在重组分集目标、反转与卡点":
            "Rebuilding episode goals, reversals, and cliffhangers",
        "正在生成场景动作和角色对白":
            "Drafting scene action and character dialogue",
        "正在检查旧名、结构、钩子与内容风险":
            "Checking name leaks, structure, hooks, and content risks",
        "正在合并故事圣经并规划分集卡":
            "Merging the story bible and planning episode cards",
        "正在执行确定性质量校验":
            "Running deterministic quality checks",
    ]
}
