#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/ScriptForge.app" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -d --entitlements :- "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"
lipo -archs "${APP_PATH}/Contents/MacOS/ScriptForge"
