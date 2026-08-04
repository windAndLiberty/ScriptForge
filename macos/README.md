# 剧擎 ScriptForge for macOS

原生 SwiftUI 版本面向 macOS 14 及以上系统，与 Windows 版对齐小说导入、一键拆书、双模型可信改编、人物改名、提示词资产、项目归档、质量门和中英文界面。

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

小说附件不进入公开仓库：

```bash
SCRIPT_FORGE_ACCEPTANCE_FILE=/absolute/path/to/novel.txt ./scripts/ci-macos.sh
```

验收检查章节完整导入、原文不截断、动态场次数、人物占位名阻断、60秒整集预算和项目归档规则。

## 数据与隐私

- 每个项目保存到应用支持目录下的独立文件夹，最近项目最多50个，超出后自动归档。
- 归档项目不自动删除，只有用户确认后才能永久删除。
- API Key 使用 macOS Keychain，服务标识为 `cn.scriptforge.mac`。
- 在线调用前必须确认接收小说片段的端点域名；修改域名后需重新确认。
- 未配置 API Key 时可使用诚实标注的本地基础改编与拆书管线。

## 编译、签名与发布

开发和无签名测试：

```bash
./scripts/ci-macos.sh
```

生成 Xcode Archive：

```bash
./scripts/build-app.sh
```

在 Xcode 的 Signing & Capabilities 中选择 Apple Developer Team，然后通过 Organizer 执行 Validate 和分发。App Store 版本使用 App Sandbox；站外版本使用 Developer ID、Hardened Runtime 和公证。导出后可运行：

```bash
./scripts/verify-release.sh /path/to/ScriptForge.app
```

功能对齐和验收门槛见 [`../docs/macos-parity.md`](../docs/macos-parity.md)。
