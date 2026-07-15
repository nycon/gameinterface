#!/usr/bin/env bash
# GamePanel Installer — Haupteinstieg (Panel-first / Pterodactyl-Style)
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALLER_DIR

# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/os.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/prompts.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/config_collect.sh"

GP_ROLE=""
GP_CONFIG_FILE=""
GP_NON_INTERACTIVE=0
GP_DOCTOR=0
GP_JOIN_FILE=""

gp_show_help() {
  cat <<'HELP'
GamePanel Installer — Panel-first (wie Pterodactyl)

Empfohlener Ablauf:
  1) Panel auf VM1 installieren
  2) Im Panel Image-Server anlegen → angezeigten curl-Befehl auf VM2 ausführen
  3) Im Panel Node anlegen → angezeigten curl-Befehl auf VM3 ausführen

Verwendung:
  sudo ./install.sh --role ROLE [FLAGS]

Rollen:
  panel          Panel-VM (Docker + Nginx + SSL + Admin)
  image-server   Image-/SFTP-Server (meist via Panel-Deploy-Befehl)
  node           Game-Node (meist via Panel-Deploy-Befehl)
  panel-local    Dev Panel im Repo (ohne Root)
  standalone     Alles auf einer Maschine

Gemeinsame Flags:
  --non-interactive          Keine Rückfragen
  --config DATEI             Optionale Env
  --doctor                   Systemprüfung
  --panel-url URL            Panel-URL (Node / Image-Server Deploy)
  --deploy-token TOKEN       Einmal-Token aus dem Panel (gpd_…)

Panel-Flags:
  --domain HOST
  --admin-email EMAIL
  --admin-password PASS
  --ssl-mode MODE            selfsigned | letsencrypt

Node/Image Legacy (nur Fallback):
  --setup-token / --join-file / --pull-image-key / --image-server-host

Beispiele:

  # VM1 Panel
  sudo ./install.sh --role panel --non-interactive \
    --domain panel.example.com --ssl-mode selfsigned \
    --admin-email admin@example.com --admin-password 'StrongPass!2026'

  # VM2 / VM3 — besser den curl-Befehl aus dem Panel kopieren, oder:
  sudo ./install.sh --role node --non-interactive \
    --panel-url https://panel.example.com \
    --deploy-token 'gpd_…' --tls-insecure
HELP
}

gp_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) gp_show_help; exit 0 ;;
      --role) GP_ROLE="${2:?}"; shift 2 ;;
      --non-interactive) GP_NON_INTERACTIVE=1; export GP_NON_INTERACTIVE; shift ;;
      --config) GP_CONFIG_FILE="${2:?}"; shift 2 ;;
      --join-file) GP_JOIN_FILE="${2:?}"; shift 2 ;;
      --doctor) GP_DOCTOR=1; shift ;;
      --domain) gp_set_cfg PANEL_DOMAIN "${2:?}"; shift 2 ;;
      --admin-email) gp_set_cfg GAMEPANEL_ADMIN_EMAIL "${2:?}"; shift 2 ;;
      --admin-password) gp_set_cfg GAMEPANEL_ADMIN_PASSWORD "${2:?}"; shift 2 ;;
      --ssl-mode) gp_set_cfg SSL_MODE "${2:?}"; shift 2 ;;
      --image-server-host)
        gp_set_cfg IMAGE_SERVER_HOST "${2:?}"
        gp_set_cfg GAMEPANEL_IMAGE_SERVER_HOST "${2}"
        shift 2
        ;;
      --panel-url) gp_set_cfg GAMEPANEL_PANEL_URL "${2:?}"; shift 2 ;;
      --deploy-token) gp_set_cfg GAMEPANEL_DEPLOY_TOKEN "${2:?}"; shift 2 ;;
      --setup-token) gp_set_cfg GAMEPANEL_SETUP_TOKEN "${2:?}"; shift 2 ;;
      --pull-image-key) gp_set_cfg GAMEPANEL_IMAGE_KEY_FROM "${2:?}"; shift 2 ;;
      --node-name) gp_set_cfg GAMEPANEL_NODE_NAME "${2:?}"; shift 2 ;;
      --tls-insecure) gp_set_cfg GAMEPANEL_PANEL_TLS_INSECURE yes; shift ;;
      --source-dir) gp_set_cfg GAMEPANEL_SOURCE_DIR "${2:?}"; shift 2 ;;
      *) gp_die "Unbekannte Option: $1 ( --help )" ;;
    esac
  done
}

gp_bootstrap() {
  if [[ "${GP_ROLE:-}" == "panel-local" ]]; then
    gp_log_init
    gp_info "GamePanel Installer — panel-local ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
    return 0
  fi

  gp_require_root
  gp_log_init
  gp_log_capture
  gp_ensure_dirs
  gp_os_load
  gp_info "GamePanel Installer — $(date -u +%Y-%m-%dT%H:%M:%SZ) arch=$(gp_detect_arch)"
  gp_os_require_supported

  if [[ -n "${GP_JOIN_FILE}" ]]; then
    [[ -f "$GP_JOIN_FILE" ]] || gp_die "Join-Datei fehlt: $GP_JOIN_FILE"
    gp_load_config "$GP_JOIN_FILE"
    gp_ok "Join-Datei geladen: $GP_JOIN_FILE"
  fi

  local cfg="${GP_CONFIG_FILE:-}"
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    gp_load_config "$cfg"
  elif [[ -f "${GAMEPANEL_ETC}/installer.env" ]]; then
    gp_load_config "${GAMEPANEL_ETC}/installer.env"
  fi
}

gp_prepare_role_config() {
  case "$1" in
    panel) gp_collect_panel_config ;;
    image-server) gp_collect_image_server_config ;;
    node) gp_collect_node_config ;;
    panel-local|standalone|database|worker) ;;
    *) ;;
  esac
  if [[ "$1" != "panel-local" ]]; then
    touch "${GAMEPANEL_ETC}/installer.env"
    gp_merge_env_key GP_ROLE "$1" || true
  fi
}

gp_dispatch_role() {
  local role="$1"
  case "$role" in
    standalone) bash "${INSTALLER_DIR}/install-all-in-one.sh" standalone ;;
    panel) bash "${INSTALLER_DIR}/install-panel.sh" ;;
    panel-local) bash "${INSTALLER_DIR}/install-panel-local.sh" ;;
    node) bash "${INSTALLER_DIR}/install-node.sh" ;;
    image-server) bash "${INSTALLER_DIR}/install-image-server.sh" ;;
    database) bash "${INSTALLER_DIR}/install-all-in-one.sh" database ;;
    worker) bash "${INSTALLER_DIR}/install-all-in-one.sh" worker ;;
    *) gp_die "Unbekannte Rolle: $role" ;;
  esac
}

gp_main() {
  gp_parse_args "$@"

  if [[ "$GP_DOCTOR" -eq 1 ]]; then
    exec bash "${INSTALLER_DIR}/doctor.sh" ${GP_CONFIG_FILE:+--config "$GP_CONFIG_FILE"}
  fi

  if [[ -z "$GP_ROLE" && "$(uname -s)" == "Darwin" ]]; then
    GP_ROLE=panel-local
    gp_info "macOS erkannt — Rolle panel-local"
  fi

  if [[ "$GP_NON_INTERACTIVE" -eq 1 && -z "$GP_ROLE" ]]; then
    gp_die "--non-interactive erfordert --role"
  fi

  gp_bootstrap

  if [[ -z "$GP_ROLE" ]]; then
    gp_prompt_role GP_ROLE
  fi

  gp_log_info "Rolle: ${GP_ROLE}"
  gp_prepare_role_config "$GP_ROLE"
  gp_dispatch_role "$GP_ROLE"
  if [[ "$GP_ROLE" != "panel-local" ]]; then
    gp_set_marker "role_${GP_ROLE}" 2>/dev/null || true
  fi
  gp_ok "Installation für Rolle '${GP_ROLE}' beendet."
}

gp_main "$@"
