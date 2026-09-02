#!/usr/bin/env bash
set -euo pipefail
source_dir="${1:?source dir}"
out_dir="${2:?output dir}"
arch="${3:?arch}"
mode="${NETDISK115RS_MACOS_SIGNING_MODE:-adhoc}"
[[ "$(uname -s)" == Darwin ]] || { echo "macOS app build requires macOS" >&2; exit 69; }
case "$arch" in arm64|x86_64) ;; *) echo "unsupported macOS arch: $arch" >&2; exit 64;; esac
project="$source_dir/macos/Netdisk115.xcodeproj"
[[ -d "$project" ]] || { echo "missing Xcode project: $project" >&2; exit 66; }
tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/netdisk115-macos-build.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
build=(xcodebuild -quiet -project "$project" -scheme Netdisk115 -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$tmp/DerivedData" ARCHS="$arch" ONLY_ACTIVE_ARCH=YES ENABLE_HARDENED_RUNTIME=YES)
if [[ "$mode" == developer-id ]]; then
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for Developer ID signing}"
  : "${MACOS_CODE_SIGN_IDENTITY:?MACOS_CODE_SIGN_IDENTITY is required for Developer ID signing}"
  "${build[@]}" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGNING_ALLOWED=NO build
else
  [[ "$mode" == adhoc ]] || { echo "unknown signing mode: $mode" >&2; exit 64; }
  "${build[@]}" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build
fi
app="$tmp/DerivedData/Build/Products/Release/Netdisk115.app"
[[ -d "$app" ]] || { echo "Xcode did not produce Netdisk115.app" >&2; exit 65; }
if [[ "$mode" == developer-id ]]; then
  host_ent="$tmp/HostApp.entitlements"
  ext_ent="$tmp/FileProvider.entitlements"
  cp "$source_dir/macos/HostApp/HostApp.entitlements" "$host_ent"
  cp "$source_dir/macos/FileProvider/FileProvider.entitlements" "$ext_ent"
  export APPLE_TEAM_ID
  perl -0pi -e 's/\$\(AppIdentifierPrefix\)/$ENV{APPLE_TEAM_ID}./g; s/\$\(TeamIdentifierPrefix\)/$ENV{APPLE_TEAM_ID}./g' "$host_ent" "$ext_ent"
  # Match the literal Xcode $(...) build-setting syntax.
  # shellcheck disable=SC2016
  if grep -q '\$(' "$host_ent" "$ext_ent"; then echo "unexpanded entitlement variable" >&2; exit 65; fi
  ext="$app/Contents/PlugIns/Netdisk115FileProvider.appex"
  group_id="${APPLE_TEAM_ID}.com.netdisk115.fileprovider"
  # CODE_SIGNING_ALLOWED=NO can leave TeamIdentifierPrefix empty in processed plists.
  # Make the runtime document-group values match the Developer ID entitlements explicitly.
  /usr/libexec/PlistBuddy -c "Set :SharedAppGroupIdentifier $group_id" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SharedAppGroupIdentifier $group_id" "$ext/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :NSExtension:NSExtensionFileProviderDocumentGroup $group_id" "$ext/Contents/Info.plist"
  codesign --force --sign "$MACOS_CODE_SIGN_IDENTITY" --options runtime --timestamp --entitlements "$ext_ent" "$ext"
  codesign --force --sign "$MACOS_CODE_SIGN_IDENTITY" --options runtime --timestamp --entitlements "$host_ent" "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"
lipo "$app/Contents/MacOS/Netdisk115" -verify_arch "$arch"
lipo "$app/Contents/PlugIns/Netdisk115FileProvider.appex/Contents/MacOS/Netdisk115FileProvider" -verify_arch "$arch"
if [[ "$mode" == developer-id ]]; then
  sig="$(codesign -dv --verbose=4 "$app" 2>&1)"
  grep -q "Authority=Developer ID Application:" <<<"$sig" || { echo "app is not signed with Developer ID Application" >&2; exit 65; }
  grep -q "TeamIdentifier=$APPLE_TEAM_ID" <<<"$sig" || { echo "Developer ID team mismatch" >&2; exit 65; }
  grep -q 'flags=.*runtime' <<<"$sig" || { echo "hardened runtime missing" >&2; exit 65; }
  codesign -d --entitlements :- "$app" > "$tmp/signed-entitlements.plist" 2>/dev/null
  if [[ "$(plutil -extract com.apple.security.get-task-allow raw -o - "$tmp/signed-entitlements.plist" 2>/dev/null || true)" == true ]]; then
    echo "Developer ID build must not contain get-task-allow" >&2; exit 65
  fi
fi
mkdir -p "$out_dir"
rm -rf "$out_dir/Netdisk115.app"
ditto "$app" "$out_dir/Netdisk115.app"
echo "Built $out_dir/Netdisk115.app ($arch, $mode)"
