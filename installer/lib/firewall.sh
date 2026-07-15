#!/usr/bin/env bash
# GamePanel Installer — Firewall (ufw / firewalld)
set -euo pipefail

gp_fw_detect() {
  if gp_command_exists ufw && ufw status >/dev/null 2>&1; then
    echo ufw
  elif gp_command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
    echo firewalld
  elif gp_command_exists ufw; then
    echo ufw
  else
    echo none
  fi
}

gp_fw_allow_port() {
  local port="$1" proto="${2:-tcp}" comment="${3:-gamepanel}"
  local fw
  fw="$(gp_fw_detect)"
  case "$fw" in
    ufw)
      if ufw status | grep -qE "${port}/${proto}"; then
        gp_info "ufw: ${port}/${proto} bereits erlaubt"
      else
        ufw allow "${port}/${proto}" comment "$comment" >/dev/null || true
        gp_ok "ufw: ${port}/${proto} geöffnet"
      fi
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${port}-${proto}" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      gp_ok "firewalld: ${port}/${proto} geöffnet"
      ;;
    none)
      gp_warn "Keine Firewall-Verwaltung erkannt — Port ${port}/${proto} manuell öffnen."
      ;;
  esac
}

gp_fw_allow_service() {
  local svc="$1"
  local fw
  fw="$(gp_fw_detect)"
  case "$fw" in
    ufw)
      ufw allow "$svc" >/dev/null 2>&1 || true
      ;;
    firewalld)
      firewall-cmd --permanent --add-service="$svc" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      ;;
    none) gp_warn "Firewall: Service $svc nicht automatisch geöffnet." ;;
  esac
}

gp_fw_enable_ssh() {
  gp_fw_allow_port 22 tcp "ssh"
}

gp_fw_setup_panel() {
  local http_port="${1:-80}"
  local https_port="${2:-443}"
  gp_fw_allow_port "$http_port" tcp "gamepanel-http"
  gp_fw_allow_port "$https_port" tcp "gamepanel-https"
}

gp_fw_setup_image_server() {
  gp_fw_enable_ssh
  local ftps="${IMAGE_SERVER_ENABLE_FTPS:-no}"
  if [[ "$ftps" == "yes" ]]; then
    gp_fw_allow_port 990 tcp "gamepanel-ftps"
    gp_fw_allow_port 21 tcp "gamepanel-ftp"
  fi
}

gp_fw_setup_node() {
  gp_fw_enable_ssh
  local agent_port
  agent_port="$(gp_get_env GAMEPANEL_NODE_AGENT_PORT 9100)"
  gp_fw_allow_port "$agent_port" tcp "gamepanel-node-agent"
}
