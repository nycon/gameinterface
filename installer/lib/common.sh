#!/usr/bin/env bash
# GamePanel Installer — gemeinsame Hilfsfunktionen
set -euo pipefail

: "${INSTALLER_DIR:=$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")/.." && pwd)}"
: "${GAMEPANEL_ETC:=/etc/gamepanel}"
: "${GAMEPANEL_VAR:=/var/lib/gamepanel}"
: "${GAMEPANEL_LOG:=/var/log/gamepanel-installer.log}"
: "${GAMEPANEL_STATE:=${GAMEPANEL_ETC}/installer.state}"

# Farben (nur bei TTY)
if [[ -t 1 ]]; then
  COLOR_RESET='\033[0m'
  COLOR_BOLD='\033[1m'
  COLOR_RED='\033[0;31m'
  COLOR_GREEN='\033[0;32m'
  COLOR_YELLOW='\033[0;33m'
  COLOR_BLUE='\033[0;34m'
  COLOR_CYAN='\033[0;36m'
else
  COLOR_RESET='' COLOR_BOLD='' COLOR_RED='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_CYAN=''
fi

gp_msg() { printf '%b\n' "$*"; }
gp_info() { gp_msg "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"; }
gp_ok() { gp_msg "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
gp_warn() { gp_msg "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
gp_err() { gp_msg "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2; }
gp_die() { gp_err "$*"; exit 1; }

gp_require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    gp_die "Dieses Skript muss als root ausgeführt werden (sudo)."
  fi
}

gp_ensure_dirs() {
  local d
  for d in "$GAMEPANEL_ETC" "$GAMEPANEL_VAR" "$(dirname "$GAMEPANEL_LOG")"; do
    if [[ ! -d "$d" ]]; then
      install -d -m 0750 -o root -g root "$d"
    fi
  done
}

gp_detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) gp_die "Nicht unterstützte Architektur: $arch" ;;
  esac
}

gp_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

gp_idempotent_marker() {
  # gp_idempotent_marker <name> — true wenn Marker existiert
  local name="$1"
  [[ -f "${GAMEPANEL_ETC}/markers/${name}" ]]
}

gp_set_marker() {
  local name="$1"
  install -d -m 0750 "${GAMEPANEL_ETC}/markers"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${GAMEPANEL_ETC}/markers/${name}"
  chmod 0640 "${GAMEPANEL_ETC}/markers/${name}"
}

gp_unset_marker() {
  local name="$1"
  rm -f "${GAMEPANEL_ETC}/markers/${name}"
}

gp_run_step() {
  # gp_run_step <marker> <beschreibung> <funktion>
  local marker="$1" desc="$2" fn="$3"
  if gp_idempotent_marker "$marker"; then
    gp_info "Überspringe (bereits erledigt): $desc"
    return 0
  fi
  gp_info "$desc"
  if "$fn"; then
    gp_set_marker "$marker"
    gp_ok "$desc"
  else
    gp_die "Schritt fehlgeschlagen: $desc"
  fi
}

# Immer ausführen (kein Skip durch Marker) — für SSL / Sync
gp_run_step_always() {
  local marker="$1" desc="$2" fn="$3"
  gp_info "$desc"
  if "$fn"; then
    gp_set_marker "$marker"
    gp_ok "$desc"
  else
    gp_die "Schritt fehlgeschlagen: $desc"
  fi
}

gp_load_config() {
  local cfg="${1:-${GAMEPANEL_ETC}/installer.env}"
  if [[ -f "$cfg" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$cfg"
    set +a
    return 0
  fi
  return 1
}

gp_save_config() {
  local src="${1:-${INSTALLER_DIR}/installer.env}"
  local dest="${GAMEPANEL_ETC}/installer.env"
  gp_ensure_dirs
  if [[ -f "$src" ]]; then
    install -m 0640 -o root -g root "$src" "$dest"
    gp_ok "Konfiguration gespeichert: $dest"
  elif [[ -f "$dest" ]]; then
    gp_info "Konfiguration bereits vorhanden: $dest"
  else
    gp_warn "Keine Konfigurationsdatei zum Speichern gefunden."
  fi
}

gp_merge_env_key() {
  local key="$1" value="$2" file="${GAMEPANEL_ETC}/installer.env"
  gp_ensure_dirs
  touch "$file"
  chmod 0640 "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

gp_get_env() {
  local key="$1" default="${2:-}"
  local val
  if [[ -n "${!key+x}" ]]; then
    echo "${!key}"
    return 0
  fi
  if [[ -f "${GAMEPANEL_ETC}/installer.env" ]]; then
    val="$(grep -E "^${key}=" "${GAMEPANEL_ETC}/installer.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi
  echo "$default"
}

gp_random_secret() {
  local len="${1:-32}"
  if gp_command_exists openssl; then
    openssl rand -hex "$((len/2))"
  else
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$len"
  fi
}

gp_apt_install() {
  local pkgs=("$@")
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${pkgs[@]}"
}

gp_system_has_systemd() {
  [[ -d /run/systemd/system ]] && gp_command_exists systemctl
}

gp_curl_download() {
  local url="$1" dest="$2"
  if gp_command_exists curl; then
    curl -fsSL "$url" -o "$dest"
  elif gp_command_exists wget; then
    wget -qO "$dest" "$url"
  else
    gp_die "curl oder wget wird benötigt."
  fi
}

gp_source_all_libs() {
  local lib
  for lib in logging os firewall docker ftp systemd prompts; do
    # shellcheck disable=SC1091
    source "${INSTALLER_DIR}/lib/${lib}.sh"
  done
}
