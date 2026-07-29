#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PROJECT_DIR}/dist/ScriptForge.app"
CONTENTS_DIR="${APP_DIR}/Contents"

cd "${PROJECT_DIR}"
swift build -c release

if [[ "${APP_DIR}" != "${PROJECT_DIR}/dist/ScriptForge.app" ]]; then
  echo "Unexpected output path: ${APP_DIR}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "${PROJECT_DIR}/.build/release/ScriptForgeMac" "${CONTENTS_DIR}/MacOS/ScriptForgeMac"
cp "${PROJECT_DIR}/AppResources/Info.plist" "${CONTENTS_DIR}/Info.plist"
chmod +x "${CONTENTS_DIR}/MacOS/ScriptForgeMac"

codesign --force --deep --sign - "${APP_DIR}"
echo "Built ${APP_DIR}"
