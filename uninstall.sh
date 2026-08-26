#!/usr/bin/env bash
set -euo pipefail
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1
if [[ $EUID -eq 0 ]]; then SUDO=(); else SUDO=(sudo); fi
SERVICE_NAME="${NETDISK115RS_SERVICE_NAME:-netdisk115rs}"
MAC_LABEL="${NETDISK115RS_SERVICE_LABEL:-com.canxin.netdisk115rs}"
STATE_DIR_OVERRIDE="${NETDISK115RS_STATE_DIR:-}"
BIN_PATH_OVERRIDE="${NETDISK115RS_BIN_PATH:-}"
case "$(uname -s)" in
  Linux)
    state_dir="${STATE_DIR_OVERRIDE:-/var/lib/netdisk115rs}"
    bin_path="${BIN_PATH_OVERRIDE:-/usr/local/bin/netdisk115rs}"
    "${SUDO[@]}" systemctl disable --now "$SERVICE_NAME.service" >/dev/null 2>&1 || true
    "${SUDO[@]}" rm -f "/etc/systemd/system/$SERVICE_NAME.service" "$bin_path"
    "${SUDO[@]}" systemctl daemon-reload
    [[ $PURGE -eq 0 ]] || "${SUDO[@]}" rm -rf "$state_dir"
    ;;
  Darwin)
    state_dir="${STATE_DIR_OVERRIDE:-/Library/Application Support/netdisk115rs}"
    plist="/Library/LaunchDaemons/$MAC_LABEL.plist"
    bin_path="${BIN_PATH_OVERRIDE:-/usr/local/bin/netdisk115rs}"
    "${SUDO[@]}" launchctl bootout system "$plist" >/dev/null 2>&1 || true
    "${SUDO[@]}" rm -f "$plist" "$bin_path"
    [[ $PURGE -eq 0 ]] || "${SUDO[@]}" rm -rf "$state_dir"
    ;;
  *) echo "Unsupported OS" >&2; exit 69 ;;
esac
echo "netdisk115rs service removed$([[ $PURGE -eq 1 ]] && echo ' (state purged)' || echo ' (state preserved)')."
