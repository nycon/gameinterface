#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${INSTALLER_DIR}/lib/common.sh"
source "${INSTALLER_DIR}/lib/logging.sh"
source "${INSTALLER_DIR}/lib/os.sh"
source "${INSTALLER_DIR}/lib/docker.sh"

gp_upgrade_panel() {
  local dir="${GAMEPANEL_PANEL_DIR:-/opt/gamepanel}"
  local src="${GAMEPANEL_SOURCE_DIR:-}"
  [[ -f "${dir}/docker-compose.yml" ]] || gp_die "Kein Panel unter $dir"

  if [[ -z "$src" && -d /opt/gamepanel-src ]]; then
    src=/opt/gamepanel-src
  fi
  if [[ -n "$src" && -d "$src" ]]; then
    gp_info "Sync Quellcode: $src → $dir"
    rsync -a --delete \
      --exclude '.git' --exclude 'node_modules' --exclude 'vendor' \
      --exclude 'frontend/dist' --exclude 'backend/vendor' \
      --exclude 'deploy/nginx/certs' --exclude '.env' \
      "$src"/ "$dir"/
  fi

  gp_info "Container neu bauen (Frontend + Backend)…"
  (cd "$dir" && gp_docker_compose build --pull)
  (cd "$dir" && gp_docker_compose up -d)
  gp_info "Migrationen…"
  (cd "$dir" && gp_docker_compose exec -T backend php artisan migrate --force --no-interaction) \
    || (cd "$dir" && gp_docker_compose exec -T app php artisan migrate --force --no-interaction) \
    || gp_warn "Migration übersprungen/fehlgeschlagen"
  gp_ok "Panel aktualisiert — Hard-Reload im Browser (Ctrl+Shift+R)"
}

gp_upgrade_node() {
  local bin="${GAMEPANEL_NODE_AGENT_BIN:-/usr/local/bin/gamepanel-agent}"
  local url="${GAMEPANEL_NODE_AGENT_URL:-}"
  [[ -n "$url" ]] || { gp_info "Kein GAMEPANEL_NODE_AGENT_URL — Agent-Upgrade übersprungen"; return 0; }
  gp_curl_download "$url" "${bin}.new"
  chmod 0755 "${bin}.new"
  mv "${bin}.new" "$bin"
  systemctl restart gamepanel-agent.service
}

gp_upgrade_image_server() {
  source "${INSTALLER_DIR}/lib/ftp.sh"
  gp_image_manifest_refresh
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}

gp_main() {
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || true
  gp_os_require_supported
  local role
  role="$(gp_get_env GP_ROLE "")"
  if [[ -z "$role" ]]; then
    gp_idempotent_marker role_panel && role=panel
    gp_idempotent_marker role_standalone && role=standalone
    gp_idempotent_marker role_node && role=node
    gp_idempotent_marker role_image-server && role=image-server
  fi
  gp_info "Upgrade für Rolle: ${role:-unbekannt — versuche Panel+Image}"
  case "$role" in
    panel|standalone) gp_upgrade_panel ;;
    node) gp_upgrade_node ;;
    image-server) gp_upgrade_image_server ;;
    *)
      gp_upgrade_panel || true
      gp_upgrade_image_server || true
      gp_upgrade_node || true
      ;;
  esac
  gp_ok "Upgrade abgeschlossen"
}

gp_main "$@"
