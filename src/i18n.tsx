import {
  createContext,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type Locale = "zh-CN" | "en-US";
export type Translate = (
  key: string,
  values?: Record<string, string | number>,
) => string;

const english: Record<string, string> = {
  "剧擎": "ScriptForge",
  "改编工坊": "Adaptation Studio",
  "创作工坊": "Author Studio",
  "创作系统 / 创作工坊": "CREATIVE SYSTEM / AUTHOR STUDIO",
  "创作系统 / 一键拆书": "CREATIVE SYSTEM / BOOK ANALYSIS",
  "显示设置": "Display settings",
  "缩小界面": "Zoom out",
  "放大界面": "Zoom in",
  "切换主题": "Switch theme",
  "图片模型（可选）": "Image model (optional)",
  "语音模型（可选）": "Speech model (optional)",
  "语音角色": "Voice",
  "分镜与多媒体制作包": "Storyboard & Multimedia Package",
  "控制镜头拆分、构图、运镜、声音设计和图像提示词，但不改变已批准的故事。":
    "Controls shot breakdown, composition, camera movement, sound design, and image prompts without changing the approved story.",
  "影响镜头拆分、构图、运镜、声音设计、连续性和图像提示词。":
    "Affects shot breakdown, composition, camera movement, sound design, continuity, and image prompts.",
  "桌面应用支持 DOCX、DOC、PDF、RTF、HTML、ODT、TXT 和 Markdown":
    "The desktop app supports DOCX, DOC, PDF, RTF, HTML, ODT, TXT, and Markdown.",
  "文件读取失败": "Unable to read the document",
  "章节版本写入失败": "Unable to save imported chapter versions",
  "项目复制失败": "Unable to duplicate the project",
  "项目删除失败": "Unable to delete the project",
  "我确认仅在主动运行模型节点时，将所选上下文发送到此 API 端点":
    "I confirm that selected context may be sent to this API endpoint only when I run a model step.",
  "已创建不可变移交快照并送入改编工坊":
    "Created an immutable handoff snapshot and sent it to Adaptation Studio",
  "项目档案": "Projects",
  "提示词资产": "Prompt Assets",
  "当前项目": "CURRENT PROJECT",
  "尚未导入": "Nothing imported",
  "导入小说后开始": "Import a novel to begin",
  "创作策略 2026": "CREATIVE STRATEGY 2026",
  "爽点只是引擎，人物选择才是余味。":
    "Hooks drive the story. Character choices make it linger.",
  "默认采用精品化、类型融合、现实落点的短剧结构。":
    "Built for premium, genre-blended micro dramas with grounded stakes.",
  "模型与偏好": "Model & Preferences",
  "本地自动保存": "Local Autosave",
  "本地创作空间": "Local Workspace",
  "数据保存在此电脑": "Data stays on this computer",
  "改编工坊 / 当前项目": "ADAPTATION STUDIO / CURRENT PROJECT",
  "项目名称": "Project name",
  "本地已保存": "Saved locally",
  "重置首页": "Reset Home",
  "重置到未导入小说的初始首页":
    "Reset to the initial page with no novel imported",
  "已重置到初始首页": "Reset to the initial home page",
  "已重置到初始首页；原项目已保存在项目档案":
    "Reset complete; the previous project is saved in Projects",
  "导入小说": "Import Novel",
  "导出成稿": "Export Script",
  "改编管线运行中": "Pipeline running",
  "结构化改编管线": "Structured adaptation pipeline",
  "人物表已就绪，Flash 自动命名后可手动修改":
    "Character bible ready. Flash-generated names remain editable.",
  "人物表已就绪，角色名称可继续手动修改":
    "Character bible ready. Names remain editable.",
  "搜索": "Search",
  "知道了": "Dismiss",
  "模型设置已安全保存": "Model settings saved securely",
  "把长篇故事，": "Forge long-form stories",
  "锻造成": "into ",
  "能拍的短剧。": "shootable micro dramas.",
  "不再把整本小说塞进一次提示词。先建立故事事实、人物圣经和改名表，再规划分集、逐集生成并自动质检。":
    "Stop forcing an entire novel into one prompt. Build story facts, a character bible, and a rename map before planning, drafting, and validating each episode.",
  "导入小说文本": "Import Novel Text",
  "支持 UTF-8 编码的 TXT / MD 文件，可直接拖入窗口":
    "Supports UTF-8 TXT / MD files and drag-and-drop",
  "可靠的数据流": "RELIABLE DATA FLOW",
  "章节切片": "Chapter Segmentation",
  "完整处理长文，不再截断前 8000 字":
    "Process the full manuscript instead of truncating at 8,000 characters",
  "事实与人物": "Facts & Characters",
  "证据可回溯，统一维护角色与关系":
    "Trace evidence and maintain one consistent cast and relationship graph",
  "分集与成稿": "Episode Planning",
  "先规划后写作，连续性上下文逐集传递":
    "Plan before drafting and carry continuity forward episode by episode",
  "自动质检": "Automated QA",
  "旧名、钩子、时长、结构和风险可量化":
    "Measure old-name leaks, hooks, runtime, structure, and content risk",
  "文本拆解": "Ingest",
  "故事事实": "Story Facts",
  "人物改名": "Rename Cast",
  "分集规划": "Episode Plan",
  "逐集成稿": "Draft Episodes",
  "质量校验": "Quality Gate",
  "分镜制作": "Storyboard",
  "使用原文语言": "Use source language",
  "报告语言": "Report language",
  "简体中文": "Simplified Chinese",
  "原著章节": "Source Chapters",
  "替换文本": "Replace manuscript",
  "作者：{{author}}": "Author: {{author}}",
  "章节": "Chapters",
  "字符": "Characters",
  "已读取": "Loaded",
  "原文预览": "SOURCE PREVIEW",
  "第 {{number}} 章": "Chapter {{number}}",
  "改编规格": "Adaptation Brief",
  "目标集数": "Episode Count",
  "集": "eps",
  "单集时长": "Episode Runtime",
  "{{seconds}} 秒": "{{seconds}} sec",
  "每集场次": "Scenes per Episode",
  "模型逐集动态决定": "Model decides per episode",
  "{{seconds}} 秒 · 场次按剧情自动规划":
    "{{seconds}} sec · scenes planned from story beats",
  "模型自动规划": "Model-planned",
  "2 场 · 紧凑": "2 scenes · Tight",
  "3 场 · 标准": "3 scenes · Standard",
  "4 场 · 丰富": "4 scenes · Expanded",
  "2 场 · 极简（不推荐）": "2 scenes · Minimal (Not recommended)",
  "3 场 · 60秒标准": "3 scenes · 60-sec standard",
  "4 场 · 90秒标准": "4 scenes · 90-sec standard",
  "5 场 · 120秒标准": "5 scenes · 120-sec standard",
  "6 场 · 180秒标准": "6 scenes · 180-sec standard",
  "可拍时长预算": "Shootable Runtime Budget",
  "{{seconds}} 秒 · 建议 {{scenes}} 场":
    "{{seconds}} sec · {{scenes}} scenes recommended",
  "节拍匹配": "Pacing matched",
  "场次数偏离建议": "Scene count differs",
  "有效对白字数": "Spoken characters",
  "动作与对白总字数": "Action + dialogue",
  "对白句数": "Dialogue lines",
  "当前原文/集": "Source chars / ep",
  "当前每集平均承载 {{actual}} 字原文；{{seconds}} 秒建议约 {{capacity}} 字原文/集。建议将总集数提高到约 {{episodes}} 集，避免把章节压成梗概。":
    "Each episode currently carries {{actual}} source characters. For {{seconds}} sec, target about {{capacity}} source characters per episode. Increase to roughly {{episodes}} episodes to avoid synopsis-like compression.",
  "创作策略": "Creative Strategy",
  "精品爽剧": "Premium Hook Drama",
  "现实共鸣": "Grounded Resonance",
  "轻喜反转": "Light Comedy & Reversals",
  "自动识别题材": "Detected Genre",
  "都市异能 · 系统逆袭 · 热血轻喜":
    "Urban Fantasy · System Rise · Action Comedy",
  "强钩子": "Strong Hooks",
  "高信息密度": "High Information Density",
  "可拍性优先": "Shootability First",
  "结构化大模型管线": "Structured LLM Pipeline",
  "离线验收管线": "Offline Acceptance Pipeline",
  "{{model}} · 密钥仅保存在系统加密存储":
    "{{model}} · key stored only in system encryption",
  "需要先配置模型连接": "Configure a model connection first",
  "需要配置主模型和 Flash 模型":
    "Configure both the primary and Flash models",
  "需要完成双模型配置": "Complete the two-model setup",
  "双模型协同已就绪": "Two-model orchestration ready",
  "主模型 {{model}} · Flash {{flashModel}}":
    "Primary {{model}} · Flash {{flashModel}}",
  "无需密钥，适合流程验收与界面演示":
    "No key required; ideal for workflow acceptance and UI demos",
  "离线验收": "Offline",
  "在线精修": "Online Polish",
  "配置模型": "Configure Model",
  "分集设计": "Episode Map",
  "全剧圣经": "Series Bible",
  "剧本编辑": "Script Editor",
  "质检报告": "QA Report",
  "全剧事实圣经": "Series Source of Truth",
  "人物唯一身份": "Canonical Characters",
  "原名/别名": "Source names / aliases",
  "关系": "Relationships",
  "世界规则": "World Rules",
  "原因": "Cause",
  "道具与伏笔生命周期": "Prop & Setup Lifecycle",
  "第{{start}}集引入 · 第{{end}}集兑现":
    "Introduced ep {{start}} · payoff ep {{end}}",
  "当前状态": "Current state",
  "分集连续性契约": "Episode Continuity Contracts",
  "新增信息": "New information",
  "承接": "Transition",
  "首集开场": "Series opening",
  "角色与改编规格已就绪": "Cast and adaptation brief ready",
  "Flash 模型会自动生成角色名并允许手动修改；主模型随后逐集规划、生成和校验。":
    "The Flash model generates editable cast names; the primary model then plans, drafts, and validates each episode.",
  "系统会自动生成角色名并允许手动修改，随后完成规划、成稿和质量校验。":
    "The system generates editable cast names, then handles planning, drafting, and quality validation.",
  "{{characters}} 位主要人物 · {{chapters}} 章已就绪":
    "{{characters}} main characters · {{chapters}} chapters ready",
  "生成过程可追踪，失败不会修改原文":
    "Progress is traceable; failures never modify the manuscript",
  "正在运行…": "Running…",
  "重新生成": "Regenerate",
  "开始改编": "Start Adaptation",
  "分集卡 · {{count}} 集": "Episode Map · {{count}} episodes",
  "质检 {{score}}": "QA {{score}}",
  "卡点 · {{hook}}": "Cliffhanger · {{hook}}",
  "第 {{number}} 集": "Episode {{number}}",
  "{{count}} 场 · 已成稿": "{{count}} scenes · Drafted",
  "{{count}} 字": "{{count}} chars",
  "自动保存": "Autosaved",
  "达到初稿交付线": "Draft meets the handoff bar",
  "需要修复后再交付": "Fix issues before handoff",
  "以下检查由程序规则完成，不依赖模型自评；正式上线前仍需人工审片。":
    "These checks are deterministic and independent of model self-evaluation. Human review is still required before release.",
  "交付提示": "Handoff Notes",
  "人物改名表": "Character Rename Map",
  "旧名仅用于源文匹配；成稿会强制使用新名并检查残留。":
    "Original names are used only for source matching. Drafts enforce new names and scan for leaks.",
  "原著角色": "Source Character",
  "剧本新名": "Script Name",
  "核心主角": "Protagonist",
  "主要角色": "Main Character",
  "关键配角": "Key Supporting",
  "{{role}} · {{count}} 次": "{{role}} · {{count}} mentions",
  "{{name}}的新名字": "New name for {{name}}",
  "生成时由模型命名": "Named by model at generation",
  "等待 Flash 模型命名": "Waiting for Flash model",
  "等待自动命名": "Waiting for automatic naming",
  "已锁定": "Locked",
  "未锁定": "Unlocked",
  "长名字优先替换，避免“李慕言 / 李慕”等包含关系造成串名。":
    "Longer names are replaced first to prevent partial-name collisions.",
  "模型会在生成前一次性完成角色命名，并自动避免重名、旧名和占位称呼。":
    "The model names the cast once before generation and avoids duplicates, original names, and placeholders.",
  "Flash 模型会自动生成一次角色新名；你可以直接修改，手动姓名会被保留。":
    "The Flash model generates cast names once. You can edit them directly, and manual names are preserved.",
  "系统会自动生成一次角色新名；你可以直接修改，手动姓名会被保留。":
    "The system generates cast names once. Manual edits are preserved.",
  "交付质量": "Handoff Quality",
  "查看全部": "View all",
  "综合分": "Overall",
  "成稿后自动检查人物旧名、集场结构、钩子、时长和内容风险。":
    "After drafting, automatically check name leaks, episode structure, hooks, runtime, and content risk.",
  "遵循精品化与多元题材方向；AI 辅助内容需显著标识并进行人工复核。":
    "Designed for premium, diverse genres. AI-assisted content requires disclosure and human review.",
  "模型与安全设置": "Model & Security Settings",
  "密钥不会进入前端代码或项目文件":
    "Your key never enters frontend code or project files",
  "Electron 主进程使用系统安全存储加密；模型调用也只从主进程发起。":
    "The Electron main process encrypts it with system secure storage and makes all model calls.",
  "接口协议": "API Protocol",
  "OpenAI Responses API（推荐）": "OpenAI Responses API (Recommended)",
  "兼容 Chat Completions": "Compatible Chat Completions",
  "模型": "Model",
  "主模型": "Primary Model",
  "Flash 轻量模型": "Flash Model",
  "填写已接入的 Flash 模型 ID": "Enter the connected Flash model ID",
  "创作模型": "Creative Model",
  "高速模型": "Fast Model",
  "填写第二个模型 ID": "Enter the second model ID",
  "主模型负责分析与成稿；Flash 模型只执行一次轻量角色命名。两者共享当前 API 连接和加密密钥。":
    "The primary model handles analysis and drafting. The Flash model performs one lightweight cast-naming call. Both share this API connection and encrypted key.",
  "系统会自动调度两个模型，无需手动分配阶段；两者共享当前 API 连接和加密密钥。":
    "The system routes work across both models automatically. They share the current API connection and encrypted key.",
  "推理强度": "Reasoning Effort",
  "none · 最低延迟": "none · Lowest latency",
  "low · 默认": "low · Default",
  "medium · 质量优先": "medium · Quality first",
  "high · 高成本": "high · Higher cost",
  "已保存 {{hint}}": "Saved {{hint}}",
  "留空则保持现有密钥": "Leave blank to keep the current key",
  "取消": "Cancel",
  "保存连接": "Save Connection",
  "浏览器预览不保存密钥，请在桌面应用中配置":
    "Browser preview cannot save keys. Configure this in the desktop app.",
  "保存失败": "Save failed",
  "新建改编项目": "New Adaptation Project",
  "题材": "Genre",
  "规格": "Format",
  "约": "approx.",
  "一句话梗概": "Logline",
  "生成方式": "Generation Mode",
  "提示：AI辅助内容，须经编剧、制片与合规人员复核。":
    "Notice: AI-assisted content requires review by writers, producers, and compliance staff.",
  "{{chapters}}章 · {{episodes}}集":
    "{{chapters}} chapters · {{episodes}} episodes",
  "已拆解 {{chapters}} 章并识别 {{characters}} 位主要人物":
    "Parsed {{chapters}} chapters and identified {{characters}} main characters",
  "已导入《{{title}}》": "Imported “{{title}}”",
  "已完成 {{episodes}} 集，质检 {{score}} 分":
    "Completed {{episodes}} episodes · QA score {{score}}",
  "成稿已生成，但未通过完整度质量门（{{score}} 分）":
    "Draft generated, but it did not pass the completeness gate ({{score}})",
  "自动重写后仍有分集未达到完整成稿线，请在质检报告中查看具体问题。":
    "Some episodes remain below the completeness bar after automatic rewriting. Review the QA report for details.",
  "自动重写后仍有未达线分集：{{detail}}。成稿已保留，可查看质检报告或重新生成。":
    "Some episodes remain below the bar after rewriting: {{detail}}. The draft is preserved; review QA or regenerate.",
  "请查看质检报告中的成稿完整度":
    "Review Draft Completeness in the QA report",
  "已导出：{{path}}": "Exported to {{path}}",
  "第{{number}}集剧本编辑器": "Episode {{number}} script editor",
  "人物改名一致性": "Rename Consistency",
  "分集与场次结构": "Episode & Scene Structure",
  "开场与结尾钩子": "Opening & End Hooks",
  "对白可拍性": "Dialogue Shootability",
  "目标时长贴合": "Runtime Fit",
  "全剧连续性与去重复": "Series Continuity & Deduplication",
  "成稿完整度": "Draft Completeness",
  "内容风险初筛": "Content Risk Screening",
  "{{title}}·短剧改编": "{{title}} · Micro Drama Adaptation",
  "文本导入失败": "Text import failed",
  "文件读取失败，请确认文本为 UTF-8 编码":
    "Could not read the file. Confirm that it uses UTF-8 encoding.",
  "仅支持 txt、md 或 text 文件": "Only txt, md, or text files are supported",
  "请先导入小说文本": "Import a novel first",
  "请先在模型设置中配置 API Key":
    "Configure an API key in Model Settings first",
  "请先配置主模型和 Flash 轻量模型":
    "Configure both the primary and Flash models first",
  "请先完成双模型配置": "Complete the two-model setup first",
  "正在抽取故事事实、冲突和情绪爆点":
    "Extracting story facts, conflicts, and emotional beats",
  "正在应用人物改名表并检查重名":
    "Applying the rename map and checking duplicates",
  "正在由模型轻量生成角色新名":
    "Generating cast names with a lightweight model call",
  "正在使用 Flash 模型轻量生成角色新名":
    "Generating cast names with the Flash model",
  "正在自动整理角色名称": "Organizing cast names",
  "Flash 模型已完成角色命名，可继续手动修改":
    "Flash naming complete. You can edit the names.",
  "角色名称已生成，可继续手动修改":
    "Cast names generated. You can continue editing them.",
  "角色新名已由 Flash 模型生成":
    "Cast names generated by the Flash model",
  "角色名称已自动生成": "Cast names generated",
  "Flash 角色命名失败": "Flash cast naming failed",
  "角色自动命名失败": "Automatic cast naming failed",
  "正在重组分集目标、反转与卡点":
    "Restructuring episode goals, reversals, and cliffhangers",
  "正在生成场景动作和角色对白":
    "Generating scene action and character dialogue",
  "正在检查旧名、结构、钩子与内容风险":
    "Checking old names, structure, hooks, and content risk",
  "改编完成，已保存到本地项目":
    "Adaptation complete and saved to the local project",
  "生成失败": "Generation failed",
  "暂无可导出的剧本": "No script is available to export",
  "已导出 UTF-8 文本": "Exported UTF-8 text",
  "语言": "Language",
  "中文": "中文",
  "English": "English",
  "本地工作区 / 项目档案": "LOCAL WORKSPACE / PROJECTS",
  "创作系统 / 提示词资产": "CREATIVE SYSTEM / PROMPT ASSETS",
  "所有改编项目，都留在这台电脑。":
    "Every adaptation project stays on this computer.",
  "项目会自动保存。你可以随时切换、复制现有项目，或建立新的改编工作区。":
    "Projects autosave. Switch, duplicate, or start a new adaptation workspace at any time.",
  "项目会自动保存。最近最多保留50个，旧项目自动归档；你也可以主动归档和恢复。":
    "Projects autosave. The 50 most recent stay active; older projects are archived automatically and can be restored anytime.",
  "新建项目": "New Project",
  "本地项目": "Local Projects",
  "最近项目": "Recent Projects",
  "已归档": "Archived",
  "项目筛选": "Project filters",
  "累计章节": "Total Chapters",
  "已生成集数": "Drafted Episodes",
  "当前打开": "CURRENT",
  "已有成稿": "DRAFTED",
  "编辑中": "IN PROGRESS",
  "{{title}} · {{chapters}} 章": "{{title}} · {{chapters}} chapters",
  "尚未导入小说文本": "No novel imported",
  "人物": "Characters",
  "成稿集数": "Episodes",
  "质检": "QA",
  "更新于 {{time}}": "Updated {{time}}",
  "复制": "Duplicate",
  "返回工坊": "Return to Studio",
  "打开项目": "Open Project",
  "打开项目：{{name}}": "Open project: {{name}}",
  "归档": "Archive",
  "恢复": "Restore",
  "删除": "Delete",
  "永久删除": "Delete Permanently",
  "永久删除项目": "Permanently Delete Project",
  "永久删除项目：{{name}}": "Permanently delete project: {{name}}",
  "确定永久删除项目“{{name}}”吗？此操作无法撤销。":
    'Permanently delete "{{name}}"? This action cannot be undone.',
  "项目已归档": "Project archived",
  "项目已恢复到最近项目": "Project restored to Recent Projects",
  "项目已永久删除": "Project permanently deleted",
  "项目已永久删除，已返回初始首页":
    "Project permanently deleted. Returned to the start page.",
  "暂无最近项目": "No recent projects",
  "新建项目后会显示在这里，最多保留最近50个。":
    "New projects appear here; up to 50 recent projects are kept.",
  "暂无归档项目": "No archived projects",
  "主动归档或超过50个的旧项目会显示在这里。":
    "Projects you archive, and older projects beyond the latest 50, appear here.",
  "已新建空白改编项目": "Created a blank adaptation project",
  "{{name}} · 副本": "{{name}} · Copy",
  "项目副本已创建": "Project copy created",
  "程序硬指标、跨集语义审片与修复复验共同判定；正式上线前仍需人工审片。":
    "Deterministic checks, cross-episode review, and repair verification jointly decide delivery readiness; human review is still required before release.",
  "可信终审已通过": "Trusted review passed",
  "可信终审需要人工复核": "Trusted review needs human review",
  "可交付": "DELIVERABLE",
  "已拦截": "BLOCKED",
  "审片窗口": "Review Windows",
  "修复采纳": "Repairs Kept",
  "开放问题": "Open Issues",
  "程序复算": "Rule Recheck",
  "阻断": "BLOCKER",
  "重大": "MAJOR",
  "轻微": "MINOR",
  "原著忠实度": "Source Fidelity",
  "跨集连续性": "Cross-episode Continuity",
  "人物动机": "Character Motivation",
  "节奏推进": "Pacing",
  "钩子与卡点": "Hooks & Cliffhangers",
  "对白攻守": "Dialogue Conflict",
  "制作可行性": "Production Feasibility",
  "内容风险": "Content Risk",
  "第 {{episodes}} 集": "Episode(s) {{episodes}}",
  "修复建议：{{instruction}}": "Repair: {{instruction}}",
  "未发现阻断交付的跨集问题。":
    "No cross-episode issue blocks delivery.",
  "管线提示词": "Pipeline Prompts",
  "这里的修改会直接用于下一次在线精修改编。":
    "Changes here are used directly by the next Online Polish run.",
  "影响角色自动命名、章节事实抽取、故事圣经、分集规划和逐集成稿。":
    "Affects automatic character naming, chapter fact extraction, the story bible, episode planning, and episode drafting.",
  "影响原著事实、关键事件、情绪节点和制作提示的抽取结果。":
    "Affects extraction of source facts, key events, emotional beats, and production notes.",
  "影响人物消歧、关系、世界规则、时间线和道具生命周期。":
    "Affects character disambiguation, relationships, world rules, timelines, and prop lifecycles.",
  "影响分集核心冲突、新增信息、动态场次、转场、反转和结尾卡点。":
    "Affects episode conflicts, new information, dynamic scene counts, transitions, reversals, and cliffhangers.",
  "影响逐集动作、对白、口语感、节拍密度、状态变化和可拍性。":
    "Affects episode action, dialogue, natural speech, beat density, state changes, and shootability.",
  "{{name}}。影响范围：{{impact}}": "{{name}}. Impact: {{impact}}",
  "总编剧系统规范": "Head Writer System Rules",
  "章节事实抽取": "Chapter Fact Extraction",
  "故事圣经与分集卡": "Story Bible & Episode Cards",
  "逐集可拍成稿": "Shootable Episode Drafting",
  "全管线": "ALL STAGES",
  "故事分析": "STORY ANALYSIS",
  "连续性架构": "CONTINUITY ARCHITECTURE",
  "剧本生成": "SCRIPT DRAFTING",
  "控制忠实度、短剧节奏、可拍性和内容合规的基础提示词。":
    "Base instructions for fidelity, pacing, shootability, and content safety.",
  "逐组抽取事实、事件、情绪节点和制作提示，不提前写剧本。":
    "Extract facts, events, emotional beats, and production notes without drafting early.",
  "建立人物唯一身份、世界规则、时间线和道具生命周期，作为所有后续 Agent 的唯一事实源。":
    "Build canonical identities, world rules, timeline, and prop lifecycles as the source of truth for every downstream agent.",
  "合并章节证据，生成全剧定位、集目标、反转和结尾卡点。":
    "Merge chapter evidence into series positioning, episode goals, reversals, and cliffhangers.",
  "依据分集卡和上一集连续性生成场次、动作与对白。":
    "Generate scenes, action, and dialogue from episode cards and prior continuity.",
  "Flash 模型负责轻量命名，每集场次数由主模型动态规划；集数、时长和质量预算仍由程序注入。":
    "The Flash model handles lightweight naming, while the primary model dynamically plans each episode's scene count; episode count, runtime, and quality budgets remain programmatically enforced.",
  "模型调度策略由系统管理；集数、时长和质量预算由程序统一约束。":
    "Model routing is managed by the system; episode count, runtime, and quality budgets are enforced programmatically.",
  "已连接在线管线": "CONNECTED TO ONLINE PIPELINE",
  "恢复默认": "Restore Default",
  "提示词已恢复默认": "Prompt restored to default",
  "提示词内容": "Prompt Content",
  "{{count}} 字符 · 自动保存": "{{count}} characters · Autosaved",
  "原文章节": "Source Chapters",
  "结构化 JSON": "Structured JSON",
  "确定性质检": "Deterministic QA",
  "叙事语义初审": "Narrative Semantic Review",
  "一键拆书": "One-click Book Analysis",
  "导出报告": "Export Report",
  "正在准备全书证据": "Preparing full-book evidence",
  "一键拆书完成": "Book analysis complete",
  "全书深度拆解完成，报告已保存":
    "Deep full-book analysis complete and saved",
  "本地基础拆解完成；配置双模型后可生成深度报告":
    "Local baseline analysis complete; configure both models for a deep report",
  "一键拆书失败": "Book analysis failed",
  "报告微调需要先完成双模型配置":
    "Report revision requires both models to be configured",
  "拆书报告已按指令更新": "Book analysis report updated",
  "拆书报告微调失败": "Report revision failed",
  "暂无可导出的拆书报告": "No book analysis report to export",
  "拆书报告已导出": "Book analysis report exported",
  "一键读完全书，拆出真正可复用的写作逻辑。":
    "Read the whole book once. Extract writing logic you can actually reuse.",
  "完整覆盖章节证据，自动分析叙事结构、人物体系、爽点卖点、文笔风格和仿写方法。":
    "Cover chapter evidence end to end and analyze structure, characters, hooks, commercial appeal, style, and reusable methods.",
  "导入小说并开始": "Import Novel and Start",
  "支持 UTF-8 编码的 TXT / MD 文件":
    "Supports UTF-8 TXT and MD files",
  "全书证据切片": "Full-book Evidence Chunks",
  "长章继续按叙事边界拆分，不截断正文":
    "Long chapters split on narrative boundaries without dropping text",
  "事实分层压缩": "Hierarchical Evidence Reduction",
  "保留人物、事件、伏笔、钩子与文风信号":
    "Preserve characters, events, foreshadowing, hooks, and style signals",
  "三路专项分析": "Three Specialist Reviews",
  "结构、人物、卖点与技法分别深挖":
    "Deep-dive structure, characters, appeal, and craft separately",
  "章节证据质检": "Chapter Evidence QA",
  "每个核心判断都能返回原文章节":
    "Every major finding links back to source chapters",
  "从全书证据到可复用方法，一次完成。":
    "From full-book evidence to reusable methods in one run.",
  "系统自动完成全文覆盖、证据压缩、专项分析和完整度校验；模型分工无需手动设置。":
    "The system handles full-text coverage, evidence reduction, specialist analysis, and completeness checks; model routing is automatic.",
  "双模型深度拆书已就绪": "Dual-model deep analysis ready",
  "将使用本地基础拆书": "Local baseline analysis will be used",
  "配置双模型": "Configure Models",
  "正在一键拆书": "Analyzing Book",
  "重新一键拆书": "Run Again",
  "开始一键拆书": "Start One-click Analysis",
  "证据覆盖": "Evidence Coverage",
  "准备开始拆书": "Ready to analyze",
  "已处理 {{completed}} / {{total}} 个证据单元":
    "Processed {{completed}} / {{total}} evidence units",
  "小说已就绪，可以开始一键拆书":
    "The novel is ready for one-click analysis",
  "报告将覆盖书籍元信息、叙事结构、人物关系、爽点卖点、文笔风格与仿写指南。":
    "The report covers metadata, narrative structure, character relationships, hooks and appeal, writing style, and imitation guidance.",
  "开篇钩子与节奏曲线": "Opening Hooks & Rhythm Curve",
  "人物弧光与反派梯队": "Character Arcs & Antagonist Tiers",
  "爽点密度与商业卖点": "Payoff Density & Commercial Appeal",
  "文风证据与可复用技法": "Style Evidence & Reusable Craft",
  "拆书报告": "Book Analysis Report",
  "{{mode}} · {{chunks}} 个证据块 · 生成于 {{time}}":
    "{{mode}} · {{chunks}} evidence chunks · Generated {{time}}",
  "双模型深度分析": "Dual-model Deep Analysis",
  "本地基础分析": "Local Baseline Analysis",
  "导出 Markdown": "Export Markdown",
  "报告版本": "Report Versions",
  "质检提示": "QA Notes",
  "书籍元信息": "Book Metadata",
  "类型标签": "Genre Tags",
  "综合评分": "Overall Score",
  "一句话卖点": "One-line Appeal",
  "故事梗概": "Story Synopsis",
  "目标读者": "Target Reader",
  "叙事结构深度分析": "Narrative Structure Analysis",
  "结构归类": "Structure Classification",
  "黄金开篇": "Opening Hook",
  "节奏总览": "Rhythm Overview",
  "伏笔与回收": "Foreshadowing & Payoff",
  "暂无可靠证据": "No reliable evidence yet",
  "人物体系分析": "Character System Analysis",
  "主角": "Protagonist",
  "反派": "Antagonist",
  "配角": "Supporting Character",
  "人物关系总览": "Relationship Overview",
  "人物体系总评": "Character System Assessment",
  "叙事功能": "Narrative Function",
  "核心动机": "Core Motivation",
  "成长弧": "Character Arc",
  "爽点与卖点深度分析": "Payoff & Commercial Appeal Analysis",
  "爽点高峰": "Payoff Peak",
  "爽点低谷": "Payoff Drought",
  "平均间隔": "Average Interval",
  "文笔与写作技法分析": "Writing Style & Craft Analysis",
  "语言风格": "Language Style",
  "叙事方式": "Narration",
  "场景描写": "Scene Writing",
  "对话特色": "Dialogue",
  "情绪调动": "Emotional Control",
  "学习与仿写实操指南": "Learning & Imitation Guide",
  "结构复用方案": "Reusable Structure Blueprint",
  "仿写方向": "Imitation Directions",
  "需要规避": "Pitfalls",
  "对话微调报告": "Revise Report by Chat",
  "只修改相关段落，并保留章节证据和历史版本":
    "Change only relevant sections while preserving chapter evidence and version history",
  "例如：加强对前三章钩子和读者留存的分析":
    "Example: deepen the analysis of the first three chapters and reader retention",
  "正在更新": "Updating",
  "更新报告": "Update Report",
  "证据待复核": "Evidence pending review",
  "优势": "Strengths",
  "风险": "Risks",
};

interface I18nValue {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: Translate;
}

const I18nContext = createContext<I18nValue | null>(null);

function interpolate(
  template: string,
  values: Record<string, string | number> = {},
) {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key) =>
    String(values[key] ?? ""),
  );
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(() => {
    const saved = localStorage.getItem("scriptforge.locale.v1");
    return saved === "en-US" ? "en-US" : "zh-CN";
  });

  const value = useMemo<I18nValue>(() => {
    const t: Translate = (key, values) =>
      interpolate(locale === "en-US" ? english[key] || key : key, values);
    return {
      locale,
      setLocale: (next) => {
        localStorage.setItem("scriptforge.locale.v1", next);
        document.documentElement.lang = next;
        setLocaleState(next);
      },
      t,
    };
  }, [locale]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const value = useContext(I18nContext);
  if (!value) throw new Error("I18nProvider is missing");
  return value;
}
