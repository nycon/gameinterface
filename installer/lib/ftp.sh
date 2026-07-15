#!/usr/bin/env bash
# GamePanel Installer — SFTP / optional FTPS
set -euo pipefail

IMAGE_ROOT="${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"

gp_image_ensure_layout() {
  local root="$1"
  install -d -m 0755 -o root -g root "$root"
  install -d -m 0750 "${root}/games"
  if [[ ! -f "${root}/index.json" ]]; then
    cat > "${root}/index.json" <<'JSON'
{
  "version": 1,
  "generated_at": null,
  "games": []
}
JSON
    chmod 0644 "${root}/index.json"
  fi
}

gp_image_user_create() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local group="${IMAGE_SERVER_GROUP:-gamepanel-images}"
  if ! getent group "$group" >/dev/null 2>&1; then
    groupadd --system "$group"
  fi
  if ! id "$user" >/dev/null 2>&1; then
    useradd --system --gid "$group" --home-dir "${IMAGE_ROOT}" \
      --shell /usr/sbin/nologin --comment "GamePanel Image Server" "$user"
  fi
  chown root:root "${IMAGE_ROOT}"
  chmod 0755 "${IMAGE_ROOT}"
  chown -R "${user}:${group}" "${IMAGE_ROOT}/games"
  chmod 0750 "${IMAGE_ROOT}/games"
  [[ -f "${IMAGE_ROOT}/index.json" ]] && chown root:root "${IMAGE_ROOT}/index.json" && chmod 0644 "${IMAGE_ROOT}/index.json"
}

gp_sftp_sshd_configure() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local root="${IMAGE_ROOT}"
  local snippet="/etc/ssh/sshd_config.d/99-gamepanel-images.conf"
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat > "$snippet" <<EOF
# GamePanel Image Server — internal-sftp Chroot
Match User ${user}
    ChrootDirectory ${root}
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication no
EOF
  chmod 0644 "$snippet"
  if sshd -t 2>/dev/null; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    gp_ok "OpenSSH internal-sftp für ${user} konfiguriert"
  else
    gp_die "sshd-Konfiguration ungültig nach SFTP-Setup"
  fi
}

gp_sftp_authorized_keys() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local home="${IMAGE_ROOT}"
  local auth_dir="${home}/.ssh"
  install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$auth_dir"
  local pubkey="${IMAGE_SERVER_AUTHORIZED_KEY:-}"
  if [[ -n "$pubkey" && -f "$pubkey" ]]; then
    install -m 0600 -o "$user" -g "$(id -gn "$user")" "$pubkey" "${auth_dir}/authorized_keys"
  elif [[ -n "${IMAGE_SERVER_AUTHORIZED_KEY_DATA:-}" ]]; then
    echo "${IMAGE_SERVER_AUTHORIZED_KEY_DATA}" > "${auth_dir}/authorized_keys"
    chown "$user:$(id -gn "$user")" "${auth_dir}/authorized_keys"
    chmod 0600 "${auth_dir}/authorized_keys"
  fi
  if [[ ! -f "${home}/public-key.pem" && -f "${auth_dir}/authorized_keys" ]]; then
    cp "${auth_dir}/authorized_keys" "${home}/public-key.pem"
    chown "$user:$(id -gn "$user")" "${home}/public-key.pem"
    chmod 0644 "${home}/public-key.pem"
  fi
}

gp_image_manifest_refresh() {
  local root="${IMAGE_ROOT}"
  local index="${root}/index.json"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 - "$root" "$index" "$ts" <<'PY' || gp_warn "Manifest-Index konnte nicht aktualisiert werden."
import json, os, sys
root, index_path, ts = sys.argv[1], sys.argv[2], sys.argv[3]
games_dir = os.path.join(root, "games")
entries = []
if os.path.isdir(games_dir):
    for name in sorted(os.listdir(games_dir)):
        p = os.path.join(games_dir, name)
        if os.path.isdir(p):
            entries.append({"id": name, "path": f"games/{name}"})
data = {"version": 1, "generated_at": ts, "games": entries}
with open(index_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

gp_vsftpd_install_optional() {
  [[ "${IMAGE_SERVER_ENABLE_FTPS:-no}" == "yes" ]] || return 0
  gp_apt_install vsftpd openssl
  local cert="${IMAGE_SERVER_TLS_CERT:-/etc/ssl/certs/gamepanel-images.crt}"
  local key="${IMAGE_SERVER_TLS_KEY:-/etc/ssl/private/gamepanel-images.key}"
  if [[ ! -f "$cert" || ! -f "$key" ]]; then
    gp_warn "FTPS aktiviert aber kein TLS-Zertifikat — erstelle Self-Signed (nur Test)."
    install -d -m 0755 /etc/ssl/private
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$key" -out "$cert" \
      -subj "/CN=${IMAGE_SERVER_HOSTNAME:-gamepanel-images}" 2>/dev/null
    chmod 0600 "$key"
  fi
  cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=NO
write_enable=NO
chroot_local_user=YES
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1_2=YES
rsa_cert_file=${cert}
rsa_private_key_file=${key}
pasv_min_port=40000
pasv_max_port=40100
EOF
  gp_systemd_enable_now vsftpd
}

gp_proftpd_install_optional() {
  [[ "${IMAGE_SERVER_FTP_BACKEND:-sftp}" == "proftpd" ]] || return 0
  gp_apt_install proftpd-basic
  gp_systemd_enable_now proftpd
}

gp_image_node_access_keys() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local key_dir="/etc/gamepanel/keys/node-access"
  local auth_dir="${IMAGE_ROOT}/.ssh"
  install -d -m 0700 -o root -g root /etc/gamepanel/keys

  if [[ ! -f "${key_dir}" ]]; then
    gp_info "Erzeuge Node-Zugangs-Schlüssel (ed25519)…"
    ssh-keygen -t ed25519 -f "${key_dir}" -N "" -C "gamepanel-node-image-access" >/dev/null
    chmod 0600 "${key_dir}"
    chmod 0644 "${key_dir}.pub"
  else
    gp_info "Node-Zugangs-Schlüssel existiert bereits: ${key_dir}"
  fi

  install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$auth_dir"
  local auth_keys="${auth_dir}/authorized_keys"
  touch "$auth_keys"
  chown "$user:$(id -gn "$user")" "$auth_keys"
  chmod 0600 "$auth_keys"
  if ! grep -qF "$(cat "${key_dir}.pub")" "$auth_keys" 2>/dev/null; then
    cat "${key_dir}.pub" >> "$auth_keys"
    gp_ok "Node Public Key in authorized_keys eingetragen"
  fi
}

gp_image_server_print_credentials() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local root="${IMAGE_ROOT}"
  local host
  host="$(gp_get_env IMAGE_SERVER_HOST "")"
  host="$(gp_get_env GAMEPANEL_IMAGE_SERVER_HOST "$host")"
  [[ -n "$host" ]] || host="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$host" ]] || host="<IMAGE_SERVER_IP>"

  gp_msg ""
  gp_msg "${COLOR_BOLD}=== Image-Server Zugang (VM2) ===${COLOR_RESET}"
  gp_msg "  SFTP/SSH Host:     ${host}"
  gp_msg "  Port:              22"
  gp_msg "  Benutzer:          ${user}"
  gp_msg "  Chroot-Basis:      ${root}"
  gp_msg "  Spiele-Pfad:       ${root}/games"
  gp_msg "  Manifest:          ${root}/index.json"
  gp_msg "  Node Private Key:  /etc/gamepanel/keys/node-access"
  gp_msg "  (wird bei Deploy-Token automatisch ans Panel gemeldet — kein scp nötig)"
  gp_msg ""
}
