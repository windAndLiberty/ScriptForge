#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_DIR}/dist"
ARCHIVE_PATH="${OUTPUT_DIR}/ScriptForge.xcarchive"
MODE="${1:---archive}"

cd "${PROJECT_DIR}"
"${SCRIPT_DIR}/bootstrap-macos.sh"
mkdir -p "${OUTPUT_DIR}"

if [[ "${MODE}" == "--local" ]]; then
  DERIVED_DATA_PATH="${PROJECT_DIR}/.build/release"
  APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/ScriptForge.app"
  OUTPUT_APP_PATH="${OUTPUT_DIR}/ScriptForge.app"

  xcodebuild \
    -project ScriptForge.xcodeproj \
    -scheme ScriptForge \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    build

  ditto "${APP_PATH}" "${OUTPUT_APP_PATH}"
  codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    --options runtime \
    --entitlements AppResources/ScriptForge.entitlements \
    "${OUTPUT_APP_PATH}"

  echo "Local universal app created: ${OUTPUT_APP_PATH}"
  echo "This ad-hoc build is for local testing; public distribution still requires Developer ID or App Store signing and notarization."
  exit 0
fi

if [[ "${MODE}" != "--archive" ]]; then
  echo "Usage: $0 [--local|--archive]" >&2
  exit 2
fi

xcodebuild \
  -project ScriptForge.xcodeproj \
  -scheme ScriptForge \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "Archive created: ${ARCHIVE_PATH}"
echo "Open Xcode Organizer to validate, sign, and distribute the archive."
