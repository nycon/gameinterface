#!/usr/bin/env bash
# GamePanel Installer — Config sammeln (CLI-Flags + Auto-Defaults, keine manuelle .env-Pflicht)
set -euo pipefail

gp_detect_primary_ip() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  echo "${ip:-127.0.0.1}"
}

gp_set_cfg() {
  local key="$1" value="$2"
  [[ -z "$value" && "$value" != "0" ]] && return 0
  printf -v "$key" '%s' "$value"
  export "$key"
  if [[ ! -d "${GAMEPANEL_ETC}" ]]; then
    install -d -m 0750 -o root -g root "${GAMEPANEL_ETC}" 2>/dev/null || true
  fi
  if [[ -d "${GAMEPANEL_ETC}" ]]; then
    gp_merge_env_key "$key" "$value" 2>/dev/null || true
  fi
}

gp_require_cfg() {
  local key="$1" hint="${2:-}"
  if [[ -z "${!key:-}" ]]; then
    gp_die "Fehlender Wert: ${key}${hint:+ — $hint}"
  fi
}

# Wird von install.sh nach Flag-Parse aufgerufen
gp_apply_install_flags() {
  # Flags werden als Env gesetzt, bevor die Rolle startet
  :
}

gp_collect_panel_config() {
  local ip domain
  ip="$(gp_detect_primary_ip)"
  domain="$(gp_get_env PANEL_DOMAIN "")"
  domain="$(gp_get_env GAMEPANEL_PANEL_DOMAIN "$domain")"
  [[ -n "$domain" ]] || domain="$ip"

  if [[ "${GP_NON_INTERACTIVE:-0}" != "1" ]]; then
    gp_prompt_value PANEL_DOMAIN "Panel-Domain oder IP" "$domain"
    domain="${PANEL_DOMAIN}"
    gp_prompt_value GAMEPANEL_ADMIN_EMAIL "Admin E-Mail" "$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@gamepanel.local)"
    gp_prompt_value GAMEPANEL_ADMIN_PASSWORD "Admin-Passwort (min. 10 Zeichen)" "$(gp_get_env GAMEPANEL_ADMIN_PASSWORD "")" 1
    [[ -n "${GAMEPANEL_ADMIN_PASSWORD:-}" ]] || GAMEPANEL_ADMIN_PASSWORD="$(gp_random_secret 20)!"
    gp_prompt_value IMAGE_SERVER_HOST "Image-Server Host/IP (VM2, optional)" "$(gp_get_env IMAGE_SERVER_HOST "")"
    gp_prompt_value SSL_MODE "SSL-Modus (selfsigned|letsencrypt)" "$(gp_get_env SSL_MODE selfsigned)"
  else
    [[ -n "$(gp_get_env GAMEPANEL_ADMIN_PASSWORD "")" ]] \
      || gp_set_cfg GAMEPANEL_ADMIN_PASSWORD "$(gp_random_secret 20)!"
  fi

  gp_set_cfg PANEL_DOMAIN "$domain"
  gp_set_cfg APP_URL "$(gp_get_env APP_URL "https://${domain}")"
  gp_set_cfg SSL_MODE "$(gp_get_env SSL_MODE selfsigned)"
  gp_set_cfg SSL_EMAIL "$(gp_get_env SSL_EMAIL "$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@gamepanel.local)")"
  gp_set_cfg GAMEPANEL_ADMIN_EMAIL "$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@gamepanel.local)"
  gp_set_cfg GAMEPANEL_ADMIN_PASSWORD "$(gp_get_env GAMEPANEL_ADMIN_PASSWORD "")"
  gp_set_cfg GAMEPANEL_SOURCE_DIR "$(gp_get_env GAMEPANEL_SOURCE_DIR "$(cd "${INSTALLER_DIR}/.." && pwd)")"
  gp_set_cfg HTTP_PORT "$(gp_get_env HTTP_PORT 80)"
  gp_set_cfg HTTPS_PORT "$(gp_get_env HTTPS_PORT 443)"
  gp_set_cfg RUN_SEED true
  if [[ -n "$(gp_get_env IMAGE_SERVER_HOST "")" ]]; then
    gp_set_cfg GAMEPANEL_IMAGE_SERVER_HOST "$(gp_get_env IMAGE_SERVER_HOST "")"
  fi
  # Reverb Defaults
  gp_set_cfg BROADCAST_CONNECTION reverb
  gp_set_cfg REVERB_APP_ID gamepanel
  gp_set_cfg REVERB_APP_KEY gamepanel-key
  gp_set_cfg REVERB_APP_SECRET "$(gp_get_env REVERB_APP_SECRET "$(gp_random_secret 32)")"
}

gp_collect_image_server_config() {
  local ip
  ip="$(gp_detect_primary_ip)"
  if [[ "${GP_NON_INTERACTIVE:-0}" != "1" ]]; then
    gp_prompt_value IMAGE_SERVER_HOST "Öffentliche IP/Hostname dieses Image-Servers" \
      "$(gp_get_env IMAGE_SERVER_HOST "$ip")"
  fi
  gp_set_cfg IMAGE_SERVER_HOST "$(gp_get_env IMAGE_SERVER_HOST "$ip")"
  gp_set_cfg GAMEPANEL_IMAGE_SERVER_HOST "$(gp_get_env IMAGE_SERVER_HOST "$ip")"
  gp_set_cfg IMAGE_SERVER_ROOT "$(gp_get_env IMAGE_SERVER_ROOT /srv/gamepanel-images)"
  gp_set_cfg IMAGE_SERVER_USER "$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  gp_set_cfg IMAGE_SERVER_ENABLE_FTPS "$(gp_get_env IMAGE_SERVER_ENABLE_FTPS no)"
}

gp_collect_node_config() {
  local ip
  ip="$(gp_detect_primary_ip)"

  if [[ "${GP_NON_INTERACTIVE:-0}" != "1" ]]; then
    gp_prompt_value GAMEPANEL_PANEL_URL "Panel-URL (https://…)" "$(gp_get_env GAMEPANEL_PANEL_URL "")"
    gp_prompt_value GAMEPANEL_SETUP_TOKEN "Setup-Token vom Panel" "$(gp_get_env GAMEPANEL_SETUP_TOKEN "")" 1
    gp_prompt_value IMAGE_SERVER_HOST "Image-Server Host/IP" "$(gp_get_env IMAGE_SERVER_HOST "")"
    gp_prompt_value GAMEPANEL_NODE_NAME "Node-Name" "$(gp_get_env GAMEPANEL_NODE_NAME "node-$(hostname -s)")"
    gp_prompt_value GAMEPANEL_IMAGE_KEY_FROM \
      "SFTP-Private-Key vom Image-Server (scp: user@host:/etc/gamepanel/keys/node-access) oder leer wenn lokal vorhanden" \
      "$(gp_get_env GAMEPANEL_IMAGE_KEY_FROM "")"
  fi

  gp_set_cfg GAMEPANEL_NODE_IP "$(gp_get_env GAMEPANEL_NODE_IP "$ip")"
  gp_set_cfg GAMEPANEL_NODE_HOSTNAME "$(gp_get_env GAMEPANEL_NODE_HOSTNAME "$(hostname -s)")"
  gp_set_cfg GAMEPANEL_NODE_NAME "$(gp_get_env GAMEPANEL_NODE_NAME "node-$(hostname -s)")"
  gp_set_cfg GAMEPANEL_NODE_FQDN "$(gp_get_env GAMEPANEL_NODE_FQDN "$(hostname -f 2>/dev/null || hostname)")"
  gp_set_cfg IMAGE_SERVER_USER "$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  gp_set_cfg GAMEPANEL_IMAGE_SERVER_SSH_KEY "$(gp_get_env GAMEPANEL_IMAGE_SERVER_SSH_KEY /etc/gamepanel/keys/image-server)"
  gp_set_cfg GAMEPANEL_SOURCE_DIR "$(gp_get_env GAMEPANEL_SOURCE_DIR "$(cd "${INSTALLER_DIR}/.." && pwd)")"

  # Self-signed Panel → TLS-Insecure für Agent
  if [[ "$(gp_get_env GAMEPANEL_PANEL_TLS_INSECURE "")" == "yes" ]] \
    || [[ "$(gp_get_env SSL_MODE selfsigned)" == "selfsigned" ]]; then
    gp_set_cfg GAMEPANEL_PANEL_TLS_INSECURE yes
  fi

  gp_require_cfg GAMEPANEL_PANEL_URL "z.B. ./install.sh --role node --panel-url https://10.0.0.10 --setup-token …"
  gp_require_cfg GAMEPANEL_SETUP_TOKEN "vom Panel-Install ausgeben / join-Datei"
  gp_require_cfg IMAGE_SERVER_HOST "oder --image-server-host"
}

gp_write_node_join_file() {
  local panel_url token dest img_host
  panel_url="$(gp_get_env APP_URL "")"
  token="$(gp_get_env GAMEPANEL_SETUP_TOKEN "")"
  img_host="$(gp_get_env IMAGE_SERVER_HOST "$(gp_get_env GAMEPANEL_IMAGE_SERVER_HOST "")")"
  dest="${GAMEPANEL_ETC}/node-join.env"
  [[ -n "$panel_url" && -n "$token" ]] || return 0
  cat > "$dest" <<EOF
# Automatisch vom Panel-Installer erzeugt — auf dem Node:
#   scp root@PANEL:${dest} /tmp/node-join.env
#   sudo ./install.sh --role node --non-interactive --join-file /tmp/node-join.env \\
#     --pull-image-key root@${img_host:-IMAGE_HOST}:/etc/gamepanel/keys/node-access
GAMEPANEL_PANEL_URL=${panel_url}
GAMEPANEL_SETUP_TOKEN=${token}
GAMEPANEL_PANEL_TLS_INSECURE=$( [[ "$(gp_get_env SSL_MODE selfsigned)" == "selfsigned" ]] && echo yes || echo no )
IMAGE_SERVER_HOST=${img_host}
GAMEPANEL_IMAGE_SERVER_HOST=${img_host}
EOF
  chmod 0640 "$dest"
  gp_ok "Node-Join-Datei geschrieben: ${dest}"
}

gp_write_image_join_file() {
  local host user key dest
  host="$(gp_get_env IMAGE_SERVER_HOST "$(gp_detect_primary_ip)")"
  user="$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  key="/etc/gamepanel/keys/node-access"
  dest="${GAMEPANEL_ETC}/image-server-join.env"
  cat > "$dest" <<EOF
# Automatisch vom Image-Server-Installer — auf dem Node:
#   scp root@${host}:${key} /etc/gamepanel/keys/image-server
# oder:
#   sudo ./install.sh --role node --image-server-host ${host} --pull-image-key root@${host}:${key}
IMAGE_SERVER_HOST=${host}
GAMEPANEL_IMAGE_SERVER_HOST=${host}
IMAGE_SERVER_USER=${user}
GAMEPANEL_IMAGE_SERVER_SSH_KEY=/etc/gamepanel/keys/image-server
GAMEPANEL_IMAGE_KEY_FROM=root@${host}:${key}
EOF
  chmod 0640 "$dest"
  gp_ok "Image-Join-Datei: ${dest}"
}
