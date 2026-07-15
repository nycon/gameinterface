#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${INSTALLER_DIR}/lib/common.sh"
source "${INSTALLER_DIR}/lib/logging.sh"
source "${INSTALLER_DIR}/lib/prompts.sh"
source "${INSTALLER_DIR}/lib/docker.sh"
source "${INSTALLER_DIR}/lib/systemd.sh"

gp_uninstall_panel() {
  local dir="${GAMEPANEL_PANEL_DIR:-/opt/gamepanel}"
  if [[ -f "${dir}/docker-compose.yml" ]]; then
    gp_docker_down "$dir" || true
  fi
}

gp_uninstall_node() {
  gp_systemd_stop_disable gamepanel-agent.service
  rm -f /etc/systemd/system/gamepanel-agent.service
  systemctl daemon-reload
  rm -f "${GAMEPANEL_NODE_AGENT_BIN:-/usr/local/bin/gamepanel-agent}"
}

gp_uninstall_image() {
  rm -f /etc/ssh/sshd_config.d/99-gamepanel-images.conf
  systemctl reload ssh 2>/dev/null || true
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  id "$user" &>/dev/null && userdel "$user" 2>/dev/null || true
  getent group "${IMAGE_SERVER_GROUP:-gamepanel-images}" &>/dev/null && groupdel "${IMAGE_SERVER_GROUP:-gamepanel-images}" 2>/dev/null || true
}

gp_uninstall_worker() {
  gp_systemd_stop_disable gamepanel-worker.service
  rm -f /etc/systemd/system/gamepanel-worker.service
  systemctl daemon-reload
}

gp_main() {
  gp_require_root
  gp_log_capture
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || true
  gp_warn "Deinstallation entfernt Dienste und Marker, Datenverzeichnisse bleiben standardmäßig erhalten."
  gp_confirm "Fortfahren?" || exit 0
  gp_uninstall_panel
  gp_uninstall_node
  gp_uninstall_image
  gp_uninstall_worker
  rm -rf "${GAMEPANEL_ETC}/markers"
  gp_ok "Deinstallation abgeschlossen (Daten unter /opt/gamepanel, /srv/* manuell löschen)"
}

gp_main "$@"
