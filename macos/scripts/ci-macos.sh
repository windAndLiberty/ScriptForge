#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACCEPTANCE_FILE="${SCRIPT_FORGE_ACCEPTANCE_FILE:-}"

cd "${PROJECT_DIR}"
xcodegen generate --spec project.yml

assert_plist_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${file}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected ${key} in ${file}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

assert_plist_value AppResources/Info.plist CFBundleDisplayName "剧擎 ScriptForge"
assert_plist_value AppResources/Info.plist CFBundleIconFile ScriptForgeAura.icns
if [[ ! -f AppResources/ScriptForgeAura.icns ]]; then
  echo "Missing production app icon: AppResources/ScriptForgeAura.icns" >&2
  exit 1
fi
assert_plist_value AppResources/ScriptForge.entitlements com.apple.security.app-sandbox true
assert_plist_value AppResources/ScriptForge.entitlements com.apple.security.network.client true
assert_plist_value AppResources/ScriptForge.entitlements com.apple.security.files.user-selected.read-write true

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
