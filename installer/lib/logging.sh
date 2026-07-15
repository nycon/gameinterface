#!/usr/bin/env bash
# GamePanel Installer — Logging
set -euo pipefail

GP_LOG_INITIALIZED=0

gp_log_init() {
  if [[ "${GP_LOG_INITIALIZED}" -eq 1 ]]; then
    return 0
  fi
  local log_dir
  log_dir="$(dirname "${GAMEPANEL_LOG:-/var/log/gamepanel-installer.log}")"
  if [[ "${EUID:-0}" -eq 0 ]]; then
    install -d -m 0755 "$log_dir"
    touch "${GAMEPANEL_LOG}"
    chmod 0640 "${GAMEPANEL_LOG}"
  else
    GAMEPANEL_LOG="${TMPDIR:-/tmp}/gamepanel-installer-$$.log"
    touch "$GAMEPANEL_LOG"
  fi
  GP_LOG_INITIALIZED=1
}

gp_log() {
  local level="$1"; shift
  local msg="$*"
  gp_log_init
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" >> "$GAMEPANEL_LOG"
}

gp_log_info() { gp_log INFO "$*"; }
gp_log_warn() { gp_log WARN "$*"; }
gp_log_err() { gp_log ERROR "$*"; }

gp_log_capture() {
  # Leitet stdout/stderr zusätzlich ins Log um
  gp_log_init
  exec > >(tee -a "$GAMEPANEL_LOG") 2>&1
}
