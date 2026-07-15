#!/usr/bin/env bash
# GamePanel — Image-Server Installation (Panel-Deploy oder Standalone)
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/os.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/firewall.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/ftp.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/systemd.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/config_collect.sh"

gp_image_server_complete_panel() {
  local panel_url deploy_token host user key_path resp tls_flags=()
  panel_url="$(gp_get_env GAMEPANEL_PANEL_URL "")"
  deploy_token="$(gp_get_env GAMEPANEL_DEPLOY_TOKEN "")"
  [[ -n "$deploy_token" && -n "$panel_url" ]] || {
    gp_info "Kein Deploy-Token — Panel-Complete übersprungen"
    return 0
  }

  host="$(gp_get_env IMAGE_SERVER_HOST "$(gp_detect_primary_ip)")"
  user="$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  key_path="/etc/gamepanel/keys/node-access"
  [[ -f "$key_path" ]] || gp_die "Private Key fehlt: $key_path"

  [[ "$(gp_get_env GAMEPANEL_PANEL_TLS_INSECURE no)" == "yes" ]] && tls_flags+=(-k)

  local key_pem payload
  key_pem="$(cat "$key_path")"
  payload=$(jq -n \
    --arg deploy_token "$deploy_token" \
    --arg hostname "$host" \
    --arg username "$user" \
    --arg base_path "/images" \
    --arg protocol "sftp" \
    --arg ssh_private_key "$key_pem" \
    --argjson port 22 \
    '{
      deploy_token:$deploy_token,
      hostname:$hostname,
      port:$port,
      username:$username,
      base_path:$base_path,
      protocol:$protocol,
      ssh_private_key:$ssh_private_key
    }')

  gp_info "Melde Image-Server an Panel: ${panel_url%/}/api/install/image-server/complete"
  if ! resp=$(curl -fsS "${tls_flags[@]}" -X POST "${panel_url%/}/api/install/image-server/complete" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1); then
    gp_die "Panel Complete fehlgeschlagen: ${resp}"
  fi
  gp_ok "Image-Server im Panel registriert"
}

gp_install_image_server() {
  gp_log_info "Start Image-Server Installation"
  gp_os_require_supported
  IMAGE_ROOT="${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
  export IMAGE_ROOT
  gp_apt_install openssh-server python3 openssl rsync curl jq
  gp_run_step img_layout "Image-Verzeichnisstruktur" "_gp_img_layout"
  gp_run_step_always img_user "Image-Benutzer" gp_image_user_create
  gp_run_step_always img_sftp "SFTP (internal-sftp)" gp_sftp_sshd_configure
  gp_run_step_always img_node_keys "Node SSH-Schlüssel" gp_image_node_access_keys
  gp_run_step_always img_keys "SSH Authorized Keys (optional extra)" gp_sftp_authorized_keys
  gp_run_step img_manifest "Manifest index.json" gp_image_manifest_refresh
  gp_run_step img_ftps "Optional FTPS" gp_vsftpd_install_optional
  gp_run_step img_proftpd "Optional ProFTPd" gp_proftpd_install_optional
  gp_fw_setup_image_server
  install -d -m 0755 /var/log/gamepanel
  touch /var/log/gamepanel/image-server.log
  chmod 0640 /var/log/gamepanel/image-server.log
  gp_run_step img_panel "Panel Complete (Deploy-Token)" gp_image_server_complete_panel
  gp_run_step img_builder "Image-Builder + SteamCMD + Go" _gp_img_builder_install
  gp_image_server_print_credentials
  gp_write_image_join_file
  gp_log_info "Image-Server bereit unter ${IMAGE_ROOT}"
  gp_msg ""
  gp_msg "  Images bauen:  gp-image build cs2 --version 1.0.0"
  if [[ -n "$(gp_get_env GAMEPANEL_DEPLOY_TOKEN "")" ]]; then
    gp_msg "  Image-Server ist im Panel hinterlegt — als Nächstes Node im Panel anlegen."
  else
    gp_msg "  Empfohlen: Image-Server im Panel anlegen und Deploy-Befehl nutzen."
  fi
}

_gp_img_layout() {
  gp_image_ensure_layout "${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
}

_gp_img_builder_install() {
  bash "${INSTALLER_DIR}/install-image-builder.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || gp_load_config "${INSTALLER_DIR}/installer.env" 2>/dev/null || true
  gp_install_image_server
fi
