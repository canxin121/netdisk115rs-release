#!/usr/bin/env bash
set -euo pipefail
app="${1:?app path}"
: "${APPLE_API_KEY_PATH:?APPLE_API_KEY_PATH is required}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required}"
: "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID is required}"
[[ -d "$app" ]] || { echo "missing app: $app" >&2; exit 66; }
tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/netdisk115-notary.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
ditto -c -k --keepParent "$app" "$tmp/Netdisk115.zip"
xcrun notarytool submit "$tmp/Netdisk115.zip" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute -vv "$app"
