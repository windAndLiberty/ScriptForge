#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_DIR}/dist"
ARCHIVE_PATH="${OUTPUT_DIR}/ScriptForge.xcarchive"

cd "${PROJECT_DIR}"
"${SCRIPT_DIR}/bootstrap-macos.sh"
mkdir -p "${OUTPUT_DIR}"

xcodebuild \
  -project ScriptForge.xcodeproj \
  -scheme ScriptForge \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "Archive created: ${ARCHIVE_PATH}"
echo "Open Xcode Organizer to validate, sign, and distribute the archive."
