#!/usr/bin/env bash
set -euo pipefail

REPO="${NETDISK115RS_RELEASE_REPO:-canxin121/netdisk115rs-release}"
ARCHIVE_PATH="${NETDISK115RS_LOCAL_ARCHIVE:-}"
VERSION="${NETDISK115RS_VERSION:-latest}"
SERVICE_NAME="${NETDISK115RS_SERVICE_NAME:-netdisk115rs}"
MAC_LABEL="${NETDISK115RS_SERVICE_LABEL:-com.canxin.netdisk115rs}"
STATE_DIR_OVERRIDE="${NETDISK115RS_STATE_DIR:-}"
BIN_PATH_OVERRIDE="${NETDISK115RS_BIN_PATH:-}"
HEALTH_URL="${NETDISK115RS_HEALTH_URL:-http://127.0.0.1:8080/}"
MAC_APP_PATH_OVERRIDE="${NETDISK115RS_MAC_APP_PATH:-}"
NO_START=0

usage() {
  cat <<'USAGE'
Usage: install.sh [--archive PATH] [--version vX.Y.Z] [--no-start]

Installs netdisk115rs as an auto-starting system service on macOS or Linux.
Environment:
  NETDISK115RS_RELEASE_REPO  GitHub owner/repo (default: canxin121/netdisk115rs-release)
  NETDISK115RS_LOCAL_ARCHIVE Local .tar.gz package, used by CI/offline installs
  NETDISK115RS_VERSION       Release tag to install (default: latest)
  NETDISK115RS_RUN_USER      Account used to run the service (default: invoking user)
  NETDISK115RS_SERVICE_NAME  Linux service name override (CI/testing)
  NETDISK115RS_SERVICE_LABEL macOS launchd label override (CI/testing)
  NETDISK115RS_STATE_DIR     Runtime/state directory override (CI/testing)
  NETDISK115RS_BIN_PATH      Installed binary path override (CI/testing)
  NETDISK115RS_HEALTH_URL    Service health URL override (CI/testing)
  NETDISK115RS_MAC_APP_PATH  macOS Netdisk115.app install path override (CI/testing)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE_PATH="${2:?missing path after --archive}"; shift 2 ;;
    --version) VERSION="${2:?missing version after --version}"; shift 2 ;;
    --no-start) NO_START=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 69 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x86_64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 69 ;;
esac

if [[ $EUID -eq 0 ]]; then
  # macOS still ships Bash 3.2: under `set -u`, expanding an empty array can
  # raise "unbound variable". Use env as a transparent no-op command prefix.
  SUDO=(/usr/bin/env)
else
  command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 69; }
  SUDO=(sudo)
fi

run_user="${NETDISK115RS_RUN_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
if ! id "$run_user" >/dev/null 2>&1; then
  echo "Run user does not exist: $run_user" >&2
  exit 67
fi
run_group="$(id -gn "$run_user")"
if command -v getent >/dev/null 2>&1; then
  run_home="$(getent passwd "$run_user" | awk -F: 'NR == 1 {print $6}')"
elif command -v dscl >/dev/null 2>&1; then
  run_home="$(dscl . -read "/Users/$run_user" NFSHomeDirectory 2>/dev/null | awk 'NR == 1 {print $2}')"
else
  run_home=""
fi
if [[ -z "$run_home" ]]; then
  if [[ "$run_user" == "$(id -un)" ]]; then
    run_home="${HOME:-/tmp}"
  else
    echo "Could not determine home directory for service user: $run_user" >&2
    exit 67
  fi
fi

asset="netdisk115rs-${platform}-${arch}.tar.gz"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/netdisk115rs-install.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

if [[ -n "$ARCHIVE_PATH" ]]; then
  cp "$ARCHIVE_PATH" "$tmp/$asset"
else
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 69; }
  if [[ "$VERSION" == latest ]]; then
    base="https://github.com/${REPO}/releases/latest/download"
  else
    base="https://github.com/${REPO}/releases/download/${VERSION}"
  fi
  url="${base}/${asset}"
  echo "Downloading $url"
  curl -fL --retry 3 --retry-delay 1 -o "$tmp/$asset" "$url"
  curl -fL --retry 3 --retry-delay 1 -o "$tmp/SHA256SUMS" "${base}/SHA256SUMS"
  expected="$(awk -v file="$asset" '$2 == file {print $1}' "$tmp/SHA256SUMS")"
  [[ -n "$expected" ]] || { echo "SHA256SUMS does not contain $asset" >&2; exit 65; }
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
  fi
  [[ "$actual" == "$expected" ]] || { echo "SHA-256 mismatch for $asset" >&2; exit 65; }
fi

mkdir -p "$tmp/pkg"
tar -xzf "$tmp/$asset" -C "$tmp/pkg"
[[ -x "$tmp/pkg/netdisk115rs" ]] || { echo "Package is missing netdisk115rs" >&2; exit 65; }
[[ -f "$tmp/pkg/config.example.yaml" ]] || { echo "Package is missing config.example.yaml" >&2; exit 65; }
[[ -f "$tmp/pkg/static/index.html" ]] || { echo "Package is missing static/index.html" >&2; exit 65; }
if [[ "$platform" == macos ]]; then
  if [[ -d "$tmp/pkg/Netdisk115.app" ]]; then
    codesign --verify --deep --strict "$tmp/pkg/Netdisk115.app" || { echo "Netdisk115.app has an invalid code signature" >&2; exit 65; }
    codesign --verify --strict "$tmp/pkg/netdisk115rs" || { echo "netdisk115rs has an invalid macOS code signature" >&2; exit 65; }
  else
    echo "Warning: this legacy macOS package does not contain Netdisk115.app; installing backend only." >&2
  fi
fi

created_config=0
if [[ "$platform" == linux ]]; then
  state_dir="${STATE_DIR_OVERRIDE:-/var/lib/netdisk115rs}"
  service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  bin_path="${BIN_PATH_OVERRIDE:-/usr/local/bin/netdisk115rs}"

  "${SUDO[@]}" systemctl stop "$SERVICE_NAME.service" >/dev/null 2>&1 || true
  "${SUDO[@]}" install -d -m 0750 -o "$run_user" -g "$run_group" "$state_dir"
  "${SUDO[@]}" install -m 0755 "$tmp/pkg/netdisk115rs" "$bin_path"
  "${SUDO[@]}" rm -rf "$state_dir/static.new"
  "${SUDO[@]}" cp -R "$tmp/pkg/static" "$state_dir/static.new"
  "${SUDO[@]}" rm -rf "$state_dir/static"
  "${SUDO[@]}" mv "$state_dir/static.new" "$state_dir/static"
  if [[ ! -f "$state_dir/config.yaml" ]]; then
    "${SUDO[@]}" install -m 0600 -o "$run_user" -g "$run_group" "$tmp/pkg/config.example.yaml" "$state_dir/config.yaml"
    created_config=1
  fi
  "${SUDO[@]}" chown -R "$run_user:$run_group" "$state_dir"

  unit_tmp="$tmp/netdisk115rs.service"
  cat > "$unit_tmp" <<UNIT
[Unit]
Description=netdisk115rs backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$run_user
Group=$run_group
WorkingDirectory=$state_dir
Environment="HOME=$run_home"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$bin_path --config $state_dir/config.yaml serve
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
  "${SUDO[@]}" install -m 0644 "$unit_tmp" "$service_file"
  "${SUDO[@]}" systemctl daemon-reload
  "${SUDO[@]}" systemctl enable "$SERVICE_NAME.service" >/dev/null
  if [[ $NO_START -eq 0 ]]; then
    "${SUDO[@]}" systemctl restart "$SERVICE_NAME.service"
  fi
else
  state_dir="${STATE_DIR_OVERRIDE:-/Library/Application Support/netdisk115rs}"
  plist="/Library/LaunchDaemons/${MAC_LABEL}.plist"
  bin_path="${BIN_PATH_OVERRIDE:-/usr/local/bin/netdisk115rs}"
  app_path="${MAC_APP_PATH_OVERRIDE:-/Applications/Netdisk115.app}"
  legacy_user_app="$run_home/Applications/Netdisk115.app"

  "${SUDO[@]}" launchctl bootout system "$plist" >/dev/null 2>&1 || true
  "${SUDO[@]}" install -d -m 0750 -o "$run_user" -g "$run_group" "$state_dir"
  "${SUDO[@]}" install -d -m 0750 -o "$run_user" -g "$run_group" "$state_dir/logs"
  "${SUDO[@]}" install -m 0755 "$tmp/pkg/netdisk115rs" "$bin_path"
  if [[ -d "$tmp/pkg/Netdisk115.app" ]]; then codesign --verify --strict "$bin_path"; fi
  "${SUDO[@]}" rm -rf "$state_dir/static.new"
  "${SUDO[@]}" cp -R "$tmp/pkg/static" "$state_dir/static.new"
  "${SUDO[@]}" rm -rf "$state_dir/static"
  "${SUDO[@]}" mv "$state_dir/static.new" "$state_dir/static"
  if [[ ! -f "$state_dir/config.yaml" ]]; then
    "${SUDO[@]}" install -m 0600 -o "$run_user" -g "$run_group" "$tmp/pkg/config.example.yaml" "$state_dir/config.yaml"
    created_config=1
  fi
  "${SUDO[@]}" chown -R "$run_user:$run_group" "$state_dir"

  if [[ -d "$tmp/pkg/Netdisk115.app" ]]; then
    # Replace the whole app bundle so stale nested extensions cannot survive an upgrade.
    # Keep the old app until the new bundle's nested signatures verify.
    run_uid="$(id -u "$run_user")"
    pkill -u "$run_uid" -x Netdisk115 >/dev/null 2>&1 || true
    pkill -u "$run_uid" -x Netdisk115FileProvider >/dev/null 2>&1 || true
    app_new="${app_path}.netdisk115rs-new-$$"
    app_old="${app_path}.netdisk115rs-old-$$"
    "${SUDO[@]}" rm -rf "$app_new" "$app_old"
    "${SUDO[@]}" install -d -m 0755 "$(dirname "$app_path")"
    "${SUDO[@]}" ditto "$tmp/pkg/Netdisk115.app" "$app_new"
    codesign --verify --deep --strict "$app_new"
    if [[ -e "$app_path" ]]; then "${SUDO[@]}" mv "$app_path" "$app_old"; fi
    if ! "${SUDO[@]}" mv "$app_new" "$app_path"; then
      [[ ! -e "$app_old" ]] || "${SUDO[@]}" mv "$app_old" "$app_path"
      exit 70
    fi
    if ! codesign --verify --deep --strict "$app_path"; then
      "${SUDO[@]}" rm -rf "$app_path"
      [[ ! -e "$app_old" ]] || "${SUDO[@]}" mv "$app_old" "$app_path"
      echo "Installed Netdisk115.app failed signature verification; previous app restored" >&2
      exit 70
    fi
    "${SUDO[@]}" rm -rf "$app_old"
    # Historical development installs used ~/Applications. Remove only the exact live app
    # after the /Applications replacement is verified; backup copies are left untouched.
    if [[ "$legacy_user_app" != "$app_path" && -d "$legacy_user_app" ]]; then
      "${SUDO[@]}" rm -rf "$legacy_user_app"
    fi
    lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [[ -x "$lsregister" ]]; then
      if [[ "$(id -un)" == "$run_user" ]]; then
        "$lsregister" -f "$app_path" >/dev/null 2>&1 || true
      else
        sudo -u "$run_user" env HOME="$run_home" "$lsregister" -f "$app_path" >/dev/null 2>&1 || true
      fi
    fi
  fi

  plist_tmp="$tmp/com.canxin.netdisk115rs.plist"
  cat > "$plist_tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$MAC_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin_path</string>
    <string>--config</string>
    <string>$state_dir/config.yaml</string>
    <string>serve</string>
  </array>
  <key>WorkingDirectory</key><string>$state_dir</string>
  <key>UserName</key><string>$run_user</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$run_home</string>
    <key>PATH</key><string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>$state_dir/logs/netdisk115rs.log</string>
  <key>StandardErrorPath</key><string>$state_dir/logs/netdisk115rs.error.log</string>
</dict>
</plist>
PLIST
  "${SUDO[@]}" install -o root -g wheel -m 0644 "$plist_tmp" "$plist"
  plutil -lint "$plist" >/dev/null
  if [[ $NO_START -eq 0 ]]; then
    "${SUDO[@]}" launchctl bootstrap system "$plist"
    "${SUDO[@]}" launchctl enable "system/$MAC_LABEL"
    "${SUDO[@]}" launchctl kickstart -k "system/$MAC_LABEL"
  else
    # Leaving a valid plist in /Library/LaunchDaemons makes it available on the next boot,
    # without bootstrapping a RunAtLoad job during a --no-start install.
    "${SUDO[@]}" launchctl enable "system/$MAC_LABEL" >/dev/null 2>&1 || true
  fi
fi

if [[ $NO_START -eq 0 && $created_config -eq 1 ]]; then
  ok=0
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  if [[ $ok -ne 1 ]]; then
    echo "Service did not become healthy on $HEALTH_URL" >&2
    if [[ "$platform" == linux ]]; then
      "${SUDO[@]}" systemctl --no-pager --full status "$SERVICE_NAME.service" || true
      "${SUDO[@]}" journalctl -u "$SERVICE_NAME.service" -n 80 --no-pager || true
    else
      "${SUDO[@]}" launchctl print "system/$MAC_LABEL" || true
      tail -n 80 "$state_dir/logs/netdisk115rs.error.log" 2>/dev/null || true
    fi
    exit 70
  fi
fi

echo "netdisk115rs installed."
echo "Config/state: $state_dir"
echo "Runs as: $run_user"
if [[ "$platform" == linux ]]; then
  echo "Service: sudo systemctl status $SERVICE_NAME"
else
  echo "Service: sudo launchctl print system/$MAC_LABEL"
  if [[ -d "$tmp/pkg/Netdisk115.app" ]]; then echo "App: $app_path"; fi
fi
