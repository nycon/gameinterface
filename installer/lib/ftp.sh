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

# OpenSSH verlangt: ChrootDirectory + alle Parent-Dirs root-owned, nicht group/world-writable
gp_ssh_harden_chroot_path() {
  local path="$1"
  local cur="" part
  path="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  [[ -n "$path" && "$path" != "/" ]] || return 0

  local IFS='/'
  # shellcheck disable=SC2086
  set -- ${path#/}
  cur=""
  for part in "$@"; do
    cur="${cur}/${part}"
    [[ -d "$cur" ]] || continue
    # / selbst niemals anfassen
    [[ "$cur" == "/" ]] && continue
    chown root:root "$cur" 2>/dev/null || true
    chmod a-s,go-w "$cur" 2>/dev/null || true
    # sicherstellen dass Owner lesen+traversen kann
    chmod u+rx "$cur" 2>/dev/null || true
  done
  chown root:root "$path"
  chmod 0755 "$path"
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
  else
    # Home/Shell korrigieren falls User schon existiert
    usermod -d "${IMAGE_ROOT}" -s /usr/sbin/nologin "$user" 2>/dev/null || true
  fi
  gp_ssh_harden_chroot_path "${IMAGE_ROOT}"
  chown -R "${user}:${group}" "${IMAGE_ROOT}/games"
  chmod 0750 "${IMAGE_ROOT}/games"
  [[ -f "${IMAGE_ROOT}/index.json" ]] && chown root:root "${IMAGE_ROOT}/index.json" && chmod 0644 "${IMAGE_ROOT}/index.json"
}

gp_sftp_ensure_include() {
  local main="/etc/ssh/sshd_config"
  [[ -f "$main" ]] || return 0
  if ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' "$main"; then
    gp_info "Füge Include sshd_config.d in ${main} ein…"
    # Include möglichst früh
    if grep -qE '^\s*Include\s+' "$main"; then
      return 0
    fi
    local tmp
    tmp="$(mktemp)"
    {
      echo "Include /etc/ssh/sshd_config.d/*.conf"
      cat "$main"
    } > "$tmp"
    install -m 0644 "$tmp" "$main"
    rm -f "$tmp"
  fi
}

gp_sftp_ensure_subsystem() {
  local main="/etc/ssh/sshd_config"
  [[ -f "$main" ]] || return 0
  if ! grep -qE '^\s*Subsystem\s+sftp\s+' "$main" \
    && ! grep -qE '^\s*Subsystem\s+sftp\s+' /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
    echo "Subsystem sftp internal-sftp" > /etc/ssh/sshd_config.d/00-gamepanel-sftp-subsystem.conf
    chmod 0644 /etc/ssh/sshd_config.d/00-gamepanel-sftp-subsystem.conf
  fi
}

gp_sftp_sshd_configure() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local root="${IMAGE_ROOT}"
  # zz- damit Match-Block ganz am Ende der Include-Kette landet
  local snippet="/etc/ssh/sshd_config.d/zz-gamepanel-images.conf"
  local err

  gp_apt_install openssh-server
  install -d -m 0755 /etc/ssh/sshd_config.d
  ssh-keygen -A >/dev/null 2>&1 || true

  gp_ssh_harden_chroot_path "$root"
  gp_sftp_ensure_include
  gp_sftp_ensure_subsystem

  # Keys außerhalb des Chroots — robuster als .ssh im Jail
  install -d -m 0755 /etc/ssh/gamepanel_authorized_keys

  cat > "$snippet" <<EOF
# GamePanel Image Server - internal-sftp Chroot
Match User ${user}
    ChrootDirectory ${root}
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication no
    PubkeyAuthentication yes
    AuthorizedKeysFile /etc/ssh/gamepanel_authorized_keys/%u
EOF
  chmod 0644 "$snippet"

  # Alter Snippet-Name entfernen falls vorhanden
  rm -f /etc/ssh/sshd_config.d/99-gamepanel-images.conf

  err="$(mktemp)"
  if /usr/sbin/sshd -t -f /etc/ssh/sshd_config >"$err" 2>&1; then
    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null \
      || systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    gp_ok "OpenSSH internal-sftp fuer ${user} konfiguriert (Chroot ${root})"
    rm -f "$err"
  else
    gp_err "sshd -t fehlgeschlagen:"
    cat "$err" >&2 || true
    gp_msg "Snippet: ${snippet}"
    gp_msg "Chroot-Rechte: $(namei -l "$root" 2>/dev/null || ls -ld "$root" /srv 2>/dev/null || true)"
    rm -f "$err"
    gp_die "sshd-Konfiguration ungueltig nach SFTP-Setup — Details oben"
  fi
}

gp_sftp_authorized_keys() {
  local user="${IMAGE_SERVER_USER:-gamepanel-images}"
  local auth_keys="/etc/ssh/gamepanel_authorized_keys/${user}"
  install -d -m 0755 /etc/ssh/gamepanel_authorized_keys
  touch "$auth_keys"
  chmod 0644 "$auth_keys"
  chown root:root "$auth_keys"

  local pubkey="${IMAGE_SERVER_AUTHORIZED_KEY:-}"
  if [[ -n "$pubkey" && -f "$pubkey" ]]; then
    cat "$pubkey" > "$auth_keys"
  elif [[ -n "${IMAGE_SERVER_AUTHORIZED_KEY_DATA:-}" ]]; then
    echo "${IMAGE_SERVER_AUTHORIZED_KEY_DATA}" > "$auth_keys"
  fi
  chmod 0644 "$auth_keys"

  # Legacy-Pfad im Chroot ebenfalls spiegeln (alte Clients / Docs)
  local home="${IMAGE_ROOT}"
  local auth_dir="${home}/.ssh"
  install -d -m 0755 -o root -g root "$auth_dir"
  if [[ -s "$auth_keys" ]]; then
    install -m 0644 -o root -g root "$auth_keys" "${auth_dir}/authorized_keys"
  fi
  if [[ ! -f "${home}/public-key.pem" && -s "$auth_keys" ]]; then
    cp "$auth_keys" "${home}/public-key.pem"
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
  local auth_keys="/etc/ssh/gamepanel_authorized_keys/${user}"
  install -d -m 0700 -o root -g root /etc/gamepanel/keys
  install -d -m 0755 /etc/ssh/gamepanel_authorized_keys

  if [[ ! -f "${key_dir}" ]]; then
    gp_info "Erzeuge Node-Zugangs-Schlüssel (ed25519)…"
    ssh-keygen -t ed25519 -f "${key_dir}" -N "" -C "gamepanel-node-image-access" >/dev/null
    chmod 0600 "${key_dir}"
    chmod 0644 "${key_dir}.pub"
  else
    gp_info "Node-Zugangs-Schlüssel existiert bereits: ${key_dir}"
  fi

  touch "$auth_keys"
  chmod 0644 "$auth_keys"
  if ! grep -qF "$(cat "${key_dir}.pub")" "$auth_keys" 2>/dev/null; then
    cat "${key_dir}.pub" >> "$auth_keys"
    gp_ok "Node Public Key in AuthorizedKeysFile eingetragen"
  fi

  # Spiegel im Chroot (nur Lesen, root-owned)
  install -d -m 0755 -o root -g root "${IMAGE_ROOT}/.ssh"
  install -m 0644 -o root -g root "$auth_keys" "${IMAGE_ROOT}/.ssh/authorized_keys"
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
  gp_msg "  Image-Builder:     gp-image build <template> --version X"
  gp_msg ""
}
