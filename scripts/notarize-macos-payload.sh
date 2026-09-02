#!/usr/bin/env bash
set -euo pipefail
app="${1:?app path}"
backend="${2:?backend binary path}"
: "${APPLE_API_KEY_PATH:?APPLE_API_KEY_PATH is required}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required}"
: "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID is required}"
[[ -d "$app" ]] || { echo "missing app: $app" >&2; exit 66; }
[[ -x "$backend" ]] || { echo "missing backend: $backend" >&2; exit 66; }
codesign --verify --deep --strict "$app"
codesign --verify --strict "$backend"
tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/netdisk115-notary.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/payload"
ditto "$app" "$tmp/payload/Netdisk115.app"
cp "$backend" "$tmp/payload/netdisk115rs"
ditto -c -k --keepParent "$tmp/payload" "$tmp/netdisk115rs-macos-notary.zip"
xcrun notarytool submit "$tmp/netdisk115rs-macos-notary.zip" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait
# Apps support stapled offline tickets; standalone Mach-O binaries do not. The backend's
# notarization is still recorded by its signed code hash and is checked online by Gatekeeper.
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute -vv "$app"
spctl --assess --type execute -vv "$backend"
