#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${INSTALLER_DIR}/lib/common.sh"
source "${INSTALLER_DIR}/lib/logging.sh"
source "${INSTALLER_DIR}/lib/os.sh"
source "${INSTALLER_DIR}/lib/docker.sh"
source "${INSTALLER_DIR}/lib/firewall.sh"

GP_ISSUES=0

gp_doctor_fail() { gp_err "$*"; GP_ISSUES=$((GP_ISSUES+1)); }
gp_doctor_ok() { gp_ok "$*"; }

gp_doctor_check_root() {
  [[ "${EUID:-0}" -eq 0 ]] && gp_doctor_ok "Root-Rechte" || gp_doctor_fail "Nicht als root ausgeführt"
}

gp_doctor_check_os() {
  if gp_os_supported; then gp_doctor_ok "OS unterstützt: ${GP_OS_PRETTY:-unknown}"; else gp_doctor_fail "OS nicht unterstützt"; fi
}

gp_doctor_check_arch() {
  local a; a="$(gp_detect_arch)"; gp_doctor_ok "Architektur: $a"
}

gp_doctor_check_systemd() {
  gp_system_has_systemd && gp_doctor_ok "systemd aktiv" || gp_doctor_fail "systemd nicht verfügbar"
}

gp_doctor_check_docker() {
  if gp_command_exists docker && docker info >/dev/null 2>&1; then
    gp_doctor_ok "Docker: $(docker --version | head -1)"
  else
    gp_doctor_fail "Docker nicht installiert oder Daemon nicht erreichbar"
  fi
}

gp_doctor_check_compose() {
  if docker compose version >/dev/null 2>&1; then
    gp_doctor_ok "Compose: $(docker compose version --short 2>/dev/null || true)"
  else
    gp_doctor_fail "Docker Compose Plugin fehlt"
  fi
}

gp_doctor_check_cgroup() {
  gp_os_check_cgroup_v2 && gp_doctor_ok "cgroups v2" || gp_doctor_fail "cgroups v2 nicht aktiv (Node)"
}

gp_doctor_check_ports() {
  local ports=(22 8080 5432)
  local p
  for p in "${ports[@]}"; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${p}$"; then
      gp_doctor_ok "Port $p belegt (Dienst läuft evtl.)"
    fi
  done
}

gp_doctor_check_config() {
  if [[ -f "${GAMEPANEL_ETC}/installer.env" ]]; then
    gp_doctor_ok "Config: ${GAMEPANEL_ETC}/installer.env"
  else
    gp_doctor_fail "Keine persistierte Config in ${GAMEPANEL_ETC}"
  fi
}

gp_doctor_check_markers() {
  if [[ -d "${GAMEPANEL_ETC}/markers" ]]; then
    local c; c="$(find "${GAMEPANEL_ETC}/markers" -type f 2>/dev/null | wc -l | tr -d ' ')"
    gp_doctor_ok "Installations-Marker: $c"
  fi
}

gp_doctor_check_image_root() {
  local root="${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
  if [[ -d "$root/games" && -f "$root/index.json" ]]; then
    gp_doctor_ok "Image-Server Layout OK ($root)"
  else
    gp_info "Image-Server Layout nicht gefunden (optional)"
  fi
}

gp_doctor_check_node_runtimes() {
  local role
  role="$(gp_get_env GP_ROLE "${GP_ROLE:-}")"
  [[ "$role" == "node" || -x /usr/local/bin/gamepanel-agent || -f /opt/gamepanel/agent/config.yaml ]] || return 0

  command -v java >/dev/null 2>&1 \
    && gp_doctor_ok "Java: $(java -version 2>&1 | head -1)" \
    || gp_doctor_fail "Java fehlt (Minecraft)"

  if [[ -x /opt/gamepanel/steamcmd/steamcmd.sh ]]; then
    gp_doctor_ok "SteamCMD: /opt/gamepanel/steamcmd/steamcmd.sh"
  else
    gp_doctor_fail "SteamCMD fehlt unter /opt/gamepanel/steamcmd"
  fi

  if dpkg -l 'lib32stdc++6' 2>/dev/null | grep -q '^ii' \
    || ldconfig -p 2>/dev/null | grep -q 'libstdc++.so.6'; then
    gp_doctor_ok "lib32/Steam-Libs vorhanden"
  else
    gp_doctor_fail "lib32stdc++6 / i386 Runtime fehlt"
  fi

  if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
    gp_doctor_ok "MariaDB/MySQL aktiv"
  else
    gp_doctor_fail "MariaDB nicht aktiv (Kunden-DBs)"
  fi

  local pma_port="${GAMEPANEL_PHPMYADMIN_HTTPS_PORT:-${GAMEPANEL_PHPMYADMIN_PORT:-443}}"
  if [[ -f /opt/gamepanel/phpmyadmin/index.php ]]; then
    gp_doctor_ok "phpMyAdmin Dateien: /opt/gamepanel/phpmyadmin"
  else
    gp_doctor_fail "phpMyAdmin fehlt unter /opt/gamepanel/phpmyadmin"
  fi
  if [[ -f /etc/gamepanel/phpmyadmin-certs/fullchain.pem ]]; then
    gp_doctor_ok "phpMyAdmin TLS-Cert vorhanden"
  else
    gp_doctor_fail "phpMyAdmin TLS-Cert fehlt (/etc/gamepanel/phpmyadmin-certs)"
  fi
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${pma_port}$"; then
    gp_doctor_ok "phpMyAdmin HTTPS Port ${pma_port} lauscht"
  else
    gp_doctor_fail "phpMyAdmin Port ${pma_port} nicht offen (nginx?)"
  fi

  if systemctl is-active --quiet gamepanel-agent 2>/dev/null; then
    gp_doctor_ok "gamepanel-agent aktiv"
  else
    gp_doctor_fail "gamepanel-agent nicht aktiv"
  fi
}

gp_doctor_main() {
  local cfg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) cfg="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  gp_log_init
  gp_info "GamePanel Doctor"
  [[ -n "$cfg" && -f "$cfg" ]] && gp_load_config "$cfg" || gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || true
  gp_os_load
  gp_doctor_check_root
  gp_doctor_check_os
  gp_doctor_check_arch
  gp_doctor_check_systemd
  gp_doctor_check_cgroup
  gp_doctor_check_config
  gp_doctor_check_markers
  gp_doctor_check_image_root
  gp_doctor_check_node_runtimes
  if [[ "$(gp_get_env GP_ROLE "${GP_ROLE:-}")" != "database" && "$(gp_get_env GP_ROLE "${GP_ROLE:-}")" != "node" ]]; then
    gp_doctor_check_docker || true
    gp_doctor_check_compose || true
  fi
  gp_doctor_check_ports
  echo
  if [[ "$GP_ISSUES" -eq 0 ]]; then
    gp_ok "Doctor: keine Probleme gefunden"
    exit 0
  else
    gp_err "Doctor: $GP_ISSUES Problem(e) gefunden"
    exit 1
  fi
}

gp_doctor_main "$@"
