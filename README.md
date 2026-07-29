# 剧擎 ScriptForge（桌面版）

面向中文网文到中国微短剧的本地优先改编工作台。它不是移动端原型的简单放大，而是把一次性提示词升级为可追踪、可编辑、可验收的数据管线。

## 已实现

- UTF-8 `txt/md/text` 导入、拖放、章节拆解和全文统计
- 主要人物候选、统一改名、重名阻断与旧名残留检查
- 改编规格：集数、单集时长、每集场数、创作策略
- 离线验收管线：无 API Key 也能跑通分集、场次、对白、编辑、导出
- 在线精修管线：章节事实抽取 → 故事圣经/分集卡 → 带连续性的逐集成稿
- Huobao Drama 架构对齐：职责分离的命名、事实、圣经、规划、编剧与连续性 Agent
- 系统级双模型自动调度：高速抽取/初审，创作模型负责决策、成稿与修复，界面不暴露阶段分工
- 全剧事实圣经：人物稳定 ID/别名、世界规则、时间线、道具与伏笔生命周期
- 分集执行契约：唯一核心冲突、新增信息、入场/离场状态和跨集转场原因
- 相邻集冲突去重，阻止连续多集重复退婚、羞辱或同类事件
- 表演时长模拟：对白语速、停顿、动作节点和转场共同估算，不再只按总字数判断
- Responses API 与兼容 Chat Completions 两种协议
- 结构化输出自动降级：`json_schema` → `json_object` → 纯 JSON 提示约束
- API Key 仅在 Electron 主进程中使用，并通过系统安全存储加密
- 确定性质检：改名、集场结构、双钩子、对白量、时长拟合、内容风险初筛
- 可拍时长预算：时长联动推荐场次、对白字数、成稿字数和原文承载量
- 在线成稿质量门：识别提纲式短稿、角色过载和场次失衡，并自动重写一次
- 成稿导出移除“本集目标/冷开场/反转/卡点”等重复提纲标签，只保留可拍场景
- 本地自动保存和 UTF-8 剧本导出
- 中文 / English 界面切换，语言偏好本地记忆
- 项目档案支持自动归档、切换、新建和复制
- 提示词资产支持编辑、恢复默认，并直接接入在线精修管线
- 原生 SwiftUI macOS 版本（macOS 14+），含 Keychain 与 `.app` 构建脚本

## 运行

```powershell
cd ScriptForge
npm install
npm run dev
```

生产构建：

```powershell
npm run build
npm run dist
```

如果 Electron 下载不稳定，可临时使用镜像：

```powershell
$env:ELECTRON_MIRROR='https://npmmirror.com/mirrors/electron/'
npm install
```

## 验收

验收文本不进入公开仓库，请显式传入本机文件路径：

```powershell
npm run acceptance -- <path-to-novel.txt>
```

也可以通过 `SCRIPTFORGE_ACCEPTANCE_FIXTURE` 环境变量指定。报告与验收稿生成在
已被 Git 忽略的 `acceptance/` 目录。常规检查使用 `npm test`，构建检查使用
`npm run build`。

## 模型设置

在左下角“模型与偏好”中填写 API Base URL、模型和 API Key。默认使用 Responses API 与结构化输出；没有密钥时选择“离线验收”，所有基础功能仍可运行。

详细的数据流、质量门和相对移动端的改进见 [docs/architecture.md](docs/architecture.md)。
Huobao Drama 的来源、许可边界和架构映射见
[docs/huobao-integration.md](docs/huobao-integration.md)。

## 原生 macOS 版

SwiftUI 源码位于 [`macos/`](macos/)，可在 Mac 上用 Xcode 直接打开 `Package.swift`，也可执行：

```bash
cd macos
swift run ScriptForgeMac
bash scripts/build-app.sh
```

详细说明见 [`macos/README.md`](macos/README.md)。当前 Windows 工作机不能执行 Xcode/codesign，因此 macOS 的最终编译签名需要在真实 Mac 上完成。
