#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode command line tools are required." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "Install XcodeGen first: https://github.com/yonaskolb/XcodeGen" >&2
    exit 1
  fi
fi

cd "${PROJECT_DIR}"
xcodegen generate --spec project.yml
echo "Generated ${PROJECT_DIR}/ScriptForge.xcodeproj"
echo "Open it with: open ScriptForge.xcodeproj"
