#!/usr/bin/env bash
# GamePanel — Image-Server Installation (VM2)
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

gp_install_image_server() {
  gp_log_info "Start Image-Server Installation (VM2)"
  gp_os_require_supported
  IMAGE_ROOT="${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
  export IMAGE_ROOT
  gp_apt_install openssh-server python3 openssl rsync curl
  gp_run_step img_layout "Image-Verzeichnisstruktur" "_gp_img_layout"
  gp_run_step img_user "Image-Benutzer" gp_image_user_create
  gp_run_step img_sftp "SFTP (internal-sftp)" gp_sftp_sshd_configure
  gp_run_step img_node_keys "Node SSH-Schlüssel" gp_image_node_access_keys
  gp_run_step img_keys "SSH Authorized Keys (optional extra)" gp_sftp_authorized_keys
  gp_run_step img_manifest "Manifest index.json" gp_image_manifest_refresh
  gp_run_step img_ftps "Optional FTPS" gp_vsftpd_install_optional
  gp_run_step img_proftpd "Optional ProFTPd" gp_proftpd_install_optional
  gp_fw_setup_image_server
  install -d -m 0755 /var/log/gamepanel
  touch /var/log/gamepanel/image-server.log
  chmod 0640 /var/log/gamepanel/image-server.log
  gp_image_server_print_credentials
  gp_write_image_join_file
  gp_log_info "Image-Server bereit unter ${IMAGE_ROOT}"
  gp_msg ""
  gp_msg "${COLOR_BOLD}=== Nächster Schritt ===${COLOR_RESET}"
  gp_msg "  1) Panel installieren (VM1)"
  gp_msg "  2) Node: --pull-image-key root@$(gp_get_env IMAGE_SERVER_HOST "$(hostname -I | awk '{print $1}')"):/etc/gamepanel/keys/node-access"
  gp_msg "  Join-Datei: ${GAMEPANEL_ETC}/image-server-join.env"
}

_gp_img_layout() {
  gp_image_ensure_layout "${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || gp_load_config "${INSTALLER_DIR}/installer.env" 2>/dev/null || true
  gp_install_image_server
fi
