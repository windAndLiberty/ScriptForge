# 剧擎 ScriptForge for macOS

原生 SwiftUI 版本面向 macOS 14 及以上系统，支持网文创作工作流、小说与已有剧本导入、一键拆书、双模型可信改编、人物改名、提示词资产、项目归档、质量门、分镜与可选多媒体制作，以及中英文界面。

## 创作工坊

- 提供新书孵化、故事圣经、卷章规划、章节生产、连贯性审计和章节精修六条固定工作流，不依赖外部工作流平台。
- 工作流保存步骤、输入、候选产物和确认状态；异常退出后运行会标记为可恢复中断，可从未完成步骤继续。
- 章节生产默认单章、最多批量十章：整批章卡确认一次，正文逐章进入作者确认；AI 候选不会覆盖已接受正文。
- 章节编辑器自动保存工作稿，并提供正式版本、候选版本、段落差异和非破坏式历史恢复。
- 故事圣经卡可控制是否向模型可见；生成上下文优先当前章卡、相关设定、活动伏笔、人物状态和最近三章。
- 提示词按只读系统契约、工作流模板、项目规则和本次运行补充四层组装，支持最终提示词预览、版本历史和恢复默认；内置默认提示词只提供英文版，作者仍可将可编辑提示词改为任意语言。
- 已接受章节可导出 DOCX、Markdown 与结构化 JSON，也可创建不可变快照并移交到改编工坊。

## 通用本地导入

- 本地读取 DOCX、TXT 与 Markdown；文本支持 UTF-8、UTF-16 和 GB18030，不需要上传到转换服务。
- 可将单个受支持文件拖到窗口任意位置：当前位于创作工坊时导入为创作项目，其余页面导入到改编工坊；按钮选择与拖拽共用同一业务导入流程。
- 拖拽文件夹、多个文件或不支持的格式时会明确提示，不会创建半成品项目。
- 内容结构而非文件名决定工作流：章节型故事进入改编管线；已有剧本进入结构保真管线。
- 一键拆书的本地报告、在线模型提示词、运行进度、修订和 Markdown 导出统一跟随启动分析时的界面语言；报告保存自己的输出语言，切换界面不会造成中英混排。
- 剧本识别兼容中文“第X集/场次/画面/对白/钩子”、EPISODE/SCENE、INT./EXT. 与常见说话人格式。
- 已有剧本保留原集号、场次、动作、对白、钩子和人物名，可直接生成分镜；不会被压缩成新的目标集数或自动改名。
- 导入时提示缺集、重复集号、顺序异常、空内容单元和缺少场次标题等问题。

## 分镜与多媒体

- 已批准剧本可转换为逐集分镜制作包，包含镜号、时长、景别、运镜、9:16 构图、画面动作、台词/旁白、声音设计、连续性、制作备注和首帧提示词。
- 文本分镜拥有本地基础模式，不需要联网，也不依赖扣子、Dify、n8n 等第三方工作流平台。
- 图片与配音遵循 BYOK：在模型设置中按需填写图片模型、语音模型和音色，应用复用同一个 API Base URL 与 Keychain 中的 API Key。
- 图片或语音模型留空时对应功能关闭，不影响剧本与文本分镜。生成媒体保存在项目的 `media/` 子目录；分镜可导出为 Markdown。

## Aura 界面系统

- 应用使用原创的开合式电影场记板 Logo，Dock/Finder 图标包含完整多分辨率 ICNS，侧边栏复用同一品牌图形。
- 主窗口采用跟随系统深浅外观的流体光场与半透明材质；macOS 15 及以上使用原生 Mesh Gradient，macOS 14 使用本地径向渐变兼容实现。
- 顶部栏右侧提供“跟随系统 / 浅色 / 深色”主题菜单，选择会保存在本机并在下次启动时恢复。
- 可点击导航、工作流、章节卡片和自定义按钮提供手形鼠标指针及 Hover/按压反馈；正文编辑区域仍使用文本光标。
- 长文本编辑器使用高不透明表面，避免动态光晕影响阅读。开启“减少动态效果”时停止背景运动，开启“降低透明度”时自动改用不透明表面。
- 模型设置中的“无障碍访问”可将界面整体调整为 80%–150%，并支持 `⌘+`、`⌘-`、`⌘0`；字号、按钮、导航和关键编辑区域同步缩放，偏好会在下次启动时恢复。
- 图标按钮提供 VoiceOver 标签；增强对比度会加粗组件边界，“不以颜色区分”会为章节状态补充不同图形。
- 颜色全部通过语义主题适配浅色与深色外观，侧边栏、主工作区、浮层、编辑器和状态色拥有独立层级。

## 首次从 GitHub 获取

```bash
git clone --branch macos-native https://github.com/windAndLiberty/ScriptForge.git
cd ScriptForge/macos
./scripts/bootstrap-macos.sh
./scripts/ci-macos.sh
open ScriptForge.xcodeproj
```

`bootstrap-macos.sh` 检查 Xcode，并在已安装 Homebrew 时自动安装 XcodeGen。`project.yml` 是工程配置源，生成的 `.xcodeproj` 不进入 Git。

## 运行私有附件验收

私有小说或剧本附件不进入公开仓库；TXT 与 DOCX 均可直接验收：

```bash
SCRIPT_FORGE_ACCEPTANCE_FILE=/absolute/path/to/source.docx ./scripts/ci-macos.sh
```

验收检查内容单元完整导入、原文不截断、小说/剧本分流、剧本结构保真、动态场次数、人物占位名阻断、精确分镜时长和项目归档规则。

DOCX 使用 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 在应用沙盒内读取 OOXML；解析过程完全本地，不涉及第三方 AI 或工作流平台。

## 数据与隐私

- 每个项目保存到应用支持目录下的独立文件夹，最近项目最多50个，超出后自动归档。
- 创作项目的运行记录、候选产物和章节版本分文件原子保存；`project.json` 只保存轻量索引。
- 归档项目不自动删除，只有用户确认后才能永久删除。
- API Key 使用 macOS Keychain，服务标识为 `cn.scriptforge.mac`。
- 在线调用前必须确认接收小说片段的端点域名；修改域名后需重新确认。
- 可选图片与语音生成也只使用用户确认的 Base URL 和自备模型配置；应用不内置第三方工作流账户或密钥。
- 未配置 API Key 时仍可导入、编辑故事资料和章节、运行本地规则检查并导出；创作生成步骤会明确等待 BYOK 模型。原有本地基础改编与拆书管线保持可用。

## 编译、签名与发布

开发和无签名测试：

```bash
./scripts/ci-macos.sh
```

快速验证拖拽导入、创作/改编本地业务流程、持久化和 Xcode Debug 构建：

```bash
./scripts/smoke-macos.sh
```

生成可在本机直接运行的 Intel + Apple Silicon 通用版（临时签名，不适合公开分发）：

```bash
./scripts/build-app.sh --local
open dist/ScriptForge.app
```

生成用于正式签名和分发的 Xcode Archive：

```bash
./scripts/build-app.sh --archive
```

在 Xcode 的 Signing & Capabilities 中选择 Apple Developer Team，然后通过 Organizer 执行 Validate 和分发。App Store 版本使用 App Sandbox；站外版本使用 Developer ID、Hardened Runtime 和公证。导出后可运行：

```bash
./scripts/verify-release.sh /path/to/ScriptForge.app
```

功能对齐和验收门槛见 [`../docs/macos-parity.md`](../docs/macos-parity.md)。
