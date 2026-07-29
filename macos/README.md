# 剧擎 ScriptForge for macOS

这是与 Electron 版本共享产品逻辑的原生 SwiftUI 实现，面向 macOS 14 及以上系统。它包含中英文界面、TXT 导入、章节解析、人物统一改名、离线验收、Responses API 在线精修、逐集编辑、质量门、Keychain 密钥存储和本地自动保存。

## 用 Xcode 运行

1. 在装有 Xcode 16 或更高版本的 Mac 上打开终端。
2. 进入本目录并执行 `open Package.swift`。
3. 在 Xcode 中选择 `ScriptForgeMac` scheme 和 `My Mac`，然后点击 Run。

也可以直接使用命令行：

```bash
cd /path/to/desk/macos
swift run ScriptForgeMac
```

## 生成可双击的 `.app`

```bash
cd /path/to/desk/macos
bash scripts/build-app.sh
open dist/ScriptForge.app
```

产物为 `dist/ScriptForge.app`。脚本会按当前 Mac 的架构编译，并进行 ad-hoc 签名，适合本机验收；对外分发仍需 Apple Developer ID 签名和公证。

## 数据与密钥

- 项目自动保存到 `~/Library/Application Support/ScriptForge/project.json`。
- 模型偏好使用 `UserDefaults`。
- API Key 使用 macOS Keychain，服务标识为 `cn.scriptforge.mac`。
- 未配置 API Key 时，可使用完整的离线验收管线。

## 当前平台说明

源码由 Swift Package 管理，便于 Xcode 打开和审查。Windows 环境无法执行 Xcode、`swift build`、codesign 或 notarization；请在真实 Mac 上运行上述命令完成最终编译与签名验收。
