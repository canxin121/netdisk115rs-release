#!/usr/bin/env bash
set -euo pipefail
source_dir="${1:?source dir}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${MACOS_DEVELOPER_ID_P12_PASSWORD:?MACOS_DEVELOPER_ID_P12_PASSWORD is required}"
p12="$source_dir/macos/signing/DeveloperIDApplication.p12"
[[ -f "$p12" ]] || { echo "missing Apple-issued Developer ID certificate: $p12" >&2; exit 66; }
keychain="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/netdisk115-signing.keychain-db"
password="$(uuidgen)$(uuidgen)"
security delete-keychain "$keychain" >/dev/null 2>&1 || true
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$p12" -k "$keychain" -P "$MACOS_DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
identity="$(security find-identity -v -p codesigning "$keychain" | awk -v team="$APPLE_TEAM_ID" '$0 ~ /Developer ID Application:/ && $0 ~ "\\(" team "\\)" {print $2; exit}')"
[[ -n "$identity" ]] || { security find-identity -v -p codesigning "$keychain" >&2; echo "Developer ID Application identity for team $APPLE_TEAM_ID not found" >&2; exit 65; }
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "NETDISK115RS_MACOS_KEYCHAIN=$keychain" >> "$GITHUB_ENV"
  echo "MACOS_CODE_SIGN_IDENTITY=$identity" >> "$GITHUB_ENV"
else
  echo "NETDISK115RS_MACOS_KEYCHAIN=$keychain"
  echo "MACOS_CODE_SIGN_IDENTITY=$identity"
fi
