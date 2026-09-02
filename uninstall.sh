#!/usr/bin/env bash
set -euo pipefail
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1
if [[ $EUID -eq 0 ]]; then
  # Avoid Bash 3.2 `set -u` failures when expanding an empty array.
  SUDO=(/usr/bin/env)
else
  SUDO=(sudo)
fi
SERVICE_NAME="${NETDISK115RS_SERVICE_NAME:-netdisk115rs}"
MAC_LABEL="${NETDISK115RS_SERVICE_LABEL:-com.canxin.netdisk115rs}"
STATE_DIR_OVERRIDE="${NETDISK115RS_STATE_DIR:-}"
BIN_PATH_OVERRIDE="${NETDISK115RS_BIN_PATH:-}"
MAC_APP_PATH_OVERRIDE="${NETDISK115RS_MAC_APP_PATH:-}"
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
    run_user="${NETDISK115RS_RUN_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
    run_home="$(dscl . -read "/Users/$run_user" NFSHomeDirectory 2>/dev/null | awk 'NR == 1 {print $2}')"
    [[ -n "$run_home" ]] || run_home="${HOME:-/tmp}"
    state_dir="${STATE_DIR_OVERRIDE:-/Library/Application Support/netdisk115rs}"
    plist="/Library/LaunchDaemons/$MAC_LABEL.plist"
    bin_path="${BIN_PATH_OVERRIDE:-/usr/local/bin/netdisk115rs}"
    app_path="${MAC_APP_PATH_OVERRIDE:-/Applications/Netdisk115.app}"
    run_uid="$(id -u "$run_user")"
    pkill -u "$run_uid" -x Netdisk115 >/dev/null 2>&1 || true
    pkill -u "$run_uid" -x Netdisk115FileProvider >/dev/null 2>&1 || true
    "${SUDO[@]}" launchctl bootout system "$plist" >/dev/null 2>&1 || true
    "${SUDO[@]}" rm -f "$plist" "$bin_path"
    "${SUDO[@]}" rm -rf "$app_path"
    if [[ "$run_home/Applications/Netdisk115.app" != "$app_path" ]]; then
      "${SUDO[@]}" rm -rf "$run_home/Applications/Netdisk115.app"
    fi
    if [[ $PURGE -eq 1 ]]; then
      "${SUDO[@]}" rm -rf "$state_dir"
      "${SUDO[@]}" rm -rf "$run_home/Library/Containers/com.netdisk115.mac" "$run_home/Library/Containers/com.netdisk115.mac.fileprovider"
      if [[ -d "$run_home/Library/Group Containers" ]]; then
        while IFS= read -r group_dir; do "${SUDO[@]}" rm -rf "$group_dir"; done < <(find "$run_home/Library/Group Containers" -maxdepth 1 -type d -name '*com.netdisk115.fileprovider' -print)
      fi
    fi
    ;;
  *) echo "Unsupported OS" >&2; exit 69 ;;
esac
echo "netdisk115rs removed$([[ $PURGE -eq 1 ]] && echo ' (state/app data purged)' || echo ' (state/app data preserved)')."
