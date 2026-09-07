#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"
xcodegen generate --spec project.yml

swift test --filter 'DocumentDropTests|ScriptForgeBusinessSmokeTests'

xcodebuild \
  -project ScriptForge.xcodeproj \
  -scheme ScriptForge \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "ScriptForge smoke test passed: drag import, local business flow, persistence, and Xcode build."
