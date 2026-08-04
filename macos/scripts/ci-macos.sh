#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACCEPTANCE_FILE="${SCRIPT_FORGE_ACCEPTANCE_FILE:-}"

cd "${PROJECT_DIR}"
xcodegen generate --spec project.yml
swift test

TEST_ARGS=(
  -project ScriptForge.xcodeproj
  -scheme ScriptForge
  -destination "platform=macOS"
  -configuration Debug
  CODE_SIGNING_ALLOWED=NO
  test
)

if [[ -n "${ACCEPTANCE_FILE}" ]]; then
  SCRIPT_FORGE_ACCEPTANCE_FILE="${ACCEPTANCE_FILE}" xcodebuild "${TEST_ARGS[@]}"
else
  xcodebuild "${TEST_ARGS[@]}"
fi
