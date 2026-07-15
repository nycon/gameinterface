#!/usr/bin/env bash
# GamePanel — Game-Node Installation (VM3)
# Installiert: lib32/SteamCMD, Java (Minecraft), MariaDB (Kunden-DBs), Agent, SFTP-Key
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/os.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/systemd.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/firewall.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/config_collect.sh"

: "${GAMEPANEL_SOURCE_DIR:=$(cd "${INSTALLER_DIR}/.." && pwd)}"

gp_node_create_user() {
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  if ! id "$user" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /var/lib/gamepanel-node --shell /bin/bash "$user"
  fi
  install -d -m 0755 \
    /opt/gamepanel/agent \
    /opt/gamepanel/agent/data \
    /opt/gamepanel/steamcmd \
    /srv/gamepanel/servers \
    /srv/gamepanel/images \
    /srv/gamepanel/backups \
    /var/log/gamepanel
  chown -R "$user:$user" \
    /opt/gamepanel/agent \
    /opt/gamepanel/steamcmd \
    /srv/gamepanel \
    /var/log/gamepanel
}

gp_node_enable_i386() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  if [[ "$arch" == "amd64" ]] && ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
    gp_info "Aktiviere i386 Multiarch (Steam/lib32)…"
    dpkg --add-architecture i386
    apt-get update -qq
  fi
}

gp_node_install_deps() {
  gp_os_load
  gp_node_enable_i386

  # Basis + Netzwerk + Firewall
  gp_apt_install \
    curl wget ca-certificates gnupg jq tar gzip bzip2 xz-utils unzip zip \
    git rsync openssh-client openssh-server \
    iptables nftables uidmap dbus-user-session \
    screen tmux socat netcat-openbsd \
    python3 openssl locales

  # 32-bit / Steam Runtime (Debian 12 + Ubuntu 24.04)
  gp_apt_install lib32gcc-s1 lib32stdc++6 libc6-i386 || true
  gp_apt_install libsdl2-2.0-0 || true
  gp_apt_install libcurl4 || gp_apt_install libcurl4t64 || true
  gp_apt_install libcurl4:i386 || gp_apt_install libcurl4t64:i386 || true
  gp_apt_install libc6:i386 libstdc++6:i386 || true

  # Java für Minecraft (21 + 17 als Fallback)
  gp_apt_install openjdk-21-jre-headless || gp_apt_install openjdk-21-jre || true
  gp_apt_install openjdk-17-jre-headless || true
  if ! command -v java >/dev/null 2>&1; then
    gp_die "Java konnte nicht installiert werden (openjdk-21/17) — Minecraft-Server benötigen Java"
  fi
  gp_ok "Java: $(java -version 2>&1 | head -1)"

  # MariaDB für Kunden-Datenbanken (lokal am Node, nur localhost)
  gp_apt_install mariadb-server mariadb-client
  systemctl enable --now mariadb 2>/dev/null || systemctl enable --now mysql 2>/dev/null || true

  if [[ "${GAMEPANEL_NODE_INSTALL_DOCKER:-no}" == "yes" ]]; then
    # shellcheck disable=SC1091
    source "${INSTALLER_DIR}/lib/docker.sh"
    gp_docker_install_packages
    gp_docker_configure_service
  fi
}

gp_node_configure_mariadb() {
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  gp_info "Konfiguriere MariaDB für Kunden-DBs (localhost only)…"

  # Nur localhost — Kunden-DBs werden vom Agent lokal angelegt
  local conf="/etc/mysql/mariadb.conf.d/99-gamepanel.cnf"
  if [[ ! -d "$(dirname "$conf")" ]]; then
    conf="/etc/mysql/conf.d/99-gamepanel.cnf"
    install -d -m 0755 "$(dirname "$conf")"
  fi
  cat > "$conf" <<'EOF'
[mysqld]
bind-address = 127.0.0.1
skip-networking = 0
max_connections = 200
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
EOF

  systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null || true

  # Agent (als root-Service) nutzt unix_socket / sudo mysql
  # Zusätzlich: SQL-User gamepanel-agent für explizite Grants (Passwort in node.env)
  local db_pass
  db_pass="$(gp_get_env GAMEPANEL_NODE_MYSQL_PASSWORD "")"
  [[ -n "$db_pass" ]] || db_pass="$(gp_random_secret 24)"

  if mysql --protocol=socket -e "SELECT 1" &>/dev/null; then
    mysql --protocol=socket <<SQL
CREATE USER IF NOT EXISTS 'gamepanel-agent'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON *.* TO 'gamepanel-agent'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
  else
    mariadb --protocol=socket <<SQL
CREATE USER IF NOT EXISTS 'gamepanel-agent'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON *.* TO 'gamepanel-agent'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
  fi

  gp_merge_env_key GAMEPANEL_NODE_MYSQL_PASSWORD "$db_pass"
  gp_merge_env_key GAMEPANEL_NODE_MYSQL_USER gamepanel-agent
  gp_merge_env_key GAMEPANEL_NODE_MYSQL_HOST 127.0.0.1
  gp_merge_env_key GAMEPANEL_NODE_MYSQL_PORT 3306

  # Verify
  if mysql -u gamepanel-agent -p"${db_pass}" -h 127.0.0.1 -e 'SELECT 1' &>/dev/null \
    || mariadb -u gamepanel-agent -p"${db_pass}" -h 127.0.0.1 -e 'SELECT 1' &>/dev/null; then
    gp_ok "MariaDB bereit (User gamepanel-agent@localhost)"
  else
    gp_warn "MariaDB-User-Test fehlgeschlagen — Agent fällt ggf. auf socket/root zurück"
  fi

  # gamepanel-node in mysql-Gruppe falls vorhanden
  getent group mysql >/dev/null && usermod -aG mysql "$user" 2>/dev/null || true
}

gp_node_install_steamcmd() {
  local steam_dir="/opt/gamepanel/steamcmd"
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  install -d -m 0755 "$steam_dir"

  if [[ ! -x "${steam_dir}/steamcmd.sh" ]]; then
    gp_info "Lade SteamCMD…"
    local tmp="/tmp/steamcmd_linux.tar.gz"
    local url="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    if ! curl -fsSL --retry 5 --retry-delay 2 -o "$tmp" "$url"; then
      gp_die "SteamCMD-Download fehlgeschlagen: $url"
    fi
    tar -xzf "$tmp" -C "$steam_dir"
    rm -f "$tmp"
  fi

  chown -R "$user:$user" "$steam_dir"
  gp_info "Initialisiere SteamCMD (erster Start)…"
  # +quit bootstrap; Retry einmal
  if ! sudo -u "$user" "$steam_dir/steamcmd.sh" +quit; then
    gp_warn "SteamCMD erster Lauf meldete Fehler — zweiter Versuch…"
    sudo -u "$user" "$steam_dir/steamcmd.sh" +quit || gp_die "SteamCMD Initialisierung fehlgeschlagen"
  fi
  [[ -x "${steam_dir}/steamcmd.sh" ]] || gp_die "steamcmd.sh fehlt nach Installation"
  gp_ok "SteamCMD bereit unter ${steam_dir}"
}

gp_node_verify_runtimes() {
  local ok=1
  command -v java >/dev/null || { gp_err "java fehlt"; ok=0; }
  [[ -x /opt/gamepanel/steamcmd/steamcmd.sh ]] || { gp_err "steamcmd fehlt"; ok=0; }
  command -v mysql >/dev/null || command -v mariadb >/dev/null || { gp_err "mysql/mariadb client fehlt"; ok=0; }
  ldconfig -p 2>/dev/null | grep -q 'libstdc++.so.6.*i386\|libstdc++.so.6 (libc6)' \
    || dpkg -l 'lib32stdc++6' 2>/dev/null | grep -q '^ii' \
    || gp_warn "lib32stdc++6 ggf. unvollständig — Steam-Spiele prüfen"
  [[ "$ok" -eq 1 ]] || gp_die "Runtime-Verifikation fehlgeschlagen"
  gp_ok "Runtimes OK (Java + SteamCMD + MariaDB)"
}

gp_node_agent_version() {
  local bin="${GAMEPANEL_NODE_AGENT_BIN:-/usr/local/bin/gamepanel-agent}"
  if [[ -x "$bin" ]]; then
    "$bin" version 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

gp_node_install_agent() {
  local bin="${GAMEPANEL_NODE_AGENT_BIN:-/usr/local/bin/gamepanel-agent}"
  local agent_src_dir="${GAMEPANEL_SOURCE_DIR}/agent"
  local prebuilt="${agent_src_dir}/bin/gamepanel-agent"
  local url="${GAMEPANEL_NODE_AGENT_URL:-}"

  if [[ -x "$bin" && "${GAMEPANEL_NODE_AGENT_REINSTALL:-no}" != "yes" ]]; then
    gp_info "Agent bereits installiert: $bin ($(gp_node_agent_version))"
    return 0
  fi

  if [[ -f "$prebuilt" ]]; then
    install -m 0755 "$prebuilt" "$bin"
    gp_ok "Prebuilt Agent: $bin"
    return 0
  fi

  if ! gp_command_exists go; then
    gp_apt_install golang-go
  fi
  if gp_command_exists go && [[ -f "${agent_src_dir}/cmd/gamepanel-agent/main.go" ]]; then
    gp_info "Baue Agent (go build)…"
    (cd "$agent_src_dir" && CGO_ENABLED=0 go build -ldflags='-s -w' -o "$bin" ./cmd/gamepanel-agent)
    chmod 0755 "$bin"
    gp_ok "Agent gebaut: $bin"
    return 0
  fi

  if [[ -n "$url" ]]; then
    gp_curl_download "$url" "$bin"
    chmod 0755 "$bin"
    gp_ok "Agent von URL"
    return 0
  fi

  gp_die "Kein Agent-Binary. Prebuild: cd agent && GOOS=linux GOARCH=amd64 go build -o bin/gamepanel-agent ./cmd/gamepanel-agent"
}

gp_node_pull_image_key() {
  local key_dest="${GAMEPANEL_IMAGE_SERVER_SSH_KEY:-/etc/gamepanel/keys/image-server}"
  local from="${GAMEPANEL_IMAGE_KEY_FROM:-}"
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  install -d -m 0750 -o root -g "$user" /etc/gamepanel/keys

  if [[ -f "$key_dest" ]]; then
    chown root:"$user" "$key_dest"
    chmod 0640 "$key_dest"
    gp_ok "SFTP-Key bereits vorhanden: $key_dest"
    return 0
  fi

  if [[ -n "$from" ]]; then
    gp_info "Hole SFTP-Private-Key via scp: $from → $key_dest"
    if scp -o StrictHostKeyChecking=accept-new -o BatchMode=yes "$from" "$key_dest"; then
      chown root:"$user" "$key_dest"
      chmod 0640 "$key_dest"
      gp_ok "SFTP-Key übernommen"
      return 0
    fi
    gp_die "scp Key fehlgeschlagen (${from})."
  fi

  local key_file="${GAMEPANEL_IMAGE_SERVER_NODE_PRIVATE_KEY_FILE:-}"
  if [[ -n "$key_file" && -f "$key_file" ]]; then
    install -m 0640 -o root -g "$user" "$key_file" "$key_dest"
    return 0
  fi

  # Deploy-Token-Flow: Key kommt aus Claim-Antwort — hier nur soft-fail
  if [[ -n "$(gp_get_env GAMEPANEL_DEPLOY_TOKEN "")" ]]; then
    gp_info "SFTP-Key folgt aus Panel Claim"
    return 0
  fi

  gp_die "Kein SFTP-Key. Empfohlen: Node im Panel anlegen und Deploy-Befehl ausführen."
}

gp_node_write_sftp_key_from_claim() {
  local key_pem="$1"
  local key_dest="${GAMEPANEL_IMAGE_SERVER_SSH_KEY:-/etc/gamepanel/keys/image-server}"
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  [[ -n "$key_pem" && "$key_pem" != "null" ]] || return 0
  install -d -m 0750 -o root -g "$user" /etc/gamepanel/keys
  printf '%s\n' "$key_pem" > "$key_dest"
  chown root:"$user" "$key_dest"
  chmod 0640 "$key_dest"
  gp_ok "SFTP-Key vom Panel übernommen"
}

gp_node_write_config() {
  local config="/opt/gamepanel/agent/config.yaml"
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  local panel_url name fqdn token tls_insecure
  panel_url="$(gp_get_env GAMEPANEL_PANEL_URL "")"
  name="$(gp_get_env GAMEPANEL_NODE_NAME "$(hostname -f)")"
  fqdn="$(gp_get_env GAMEPANEL_NODE_FQDN "$(hostname -f)")"
  token="$(gp_get_env GAMEPANEL_NODE_TOKEN "")"
  tls_insecure="false"
  [[ "$(gp_get_env GAMEPANEL_PANEL_TLS_INSECURE no)" == "yes" ]] && tls_insecure="true"

  local img_host img_user img_port sftp_key
  img_host="$(gp_get_env IMAGE_SERVER_HOST "")"
  img_host="$(gp_get_env GAMEPANEL_IMAGE_SERVER_HOST "$img_host")"
  img_user="$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  img_port="$(gp_get_env GAMEPANEL_IMAGE_SERVER_PORT 22)"
  sftp_key="$(gp_get_env GAMEPANEL_IMAGE_SERVER_SSH_KEY /etc/gamepanel/keys/image-server)"

  local mysql_user mysql_pass mysql_host mysql_port
  mysql_user="$(gp_get_env GAMEPANEL_NODE_MYSQL_USER gamepanel-agent)"
  mysql_pass="$(gp_get_env GAMEPANEL_NODE_MYSQL_PASSWORD "")"
  mysql_host="$(gp_get_env GAMEPANEL_NODE_MYSQL_HOST 127.0.0.1)"
  mysql_port="$(gp_get_env GAMEPANEL_NODE_MYSQL_PORT 3306)"

  cat > "$config" <<EOF
panel:
  url: "${panel_url}"
  timeout: 30s
  tls_insecure: ${tls_insecure}

node:
  id: ""
  token: "${token}"
  name: "${name}"
  fqdn: "${fqdn}"

paths:
  agent_dir: "/opt/gamepanel/agent"
  servers_dir: "/srv/gamepanel/servers"
  images_dir: "/srv/gamepanel/images"
  backups_dir: "/srv/gamepanel/backups"
  steamcmd_dir: "/opt/gamepanel/steamcmd"
  logs_dir: "/var/log/gamepanel"

agent:
  heartbeat_interval: 30s
  job_poll_interval: 5s
  data_dir: "/opt/gamepanel/agent/data"

systemd:
  unit_prefix: "gamepanel-server"
  slice: "gamepanel.slice"

firewall:
  backend: "nftables"
  table: "gamepanel"
  chain: "allocations"

database:
  engine: "mariadb"
  host: "${mysql_host}"
  port: ${mysql_port}
  username: "${mysql_user}"
  password: "${mysql_pass}"

sftp:
  enabled: true
  host: "${img_host}"
  port: ${img_port}
  username: "${img_user}"
  password: ""
  private_key_path: "${sftp_key}"
  known_hosts_path: ""
  remote_base: "/images"

ftp:
  enabled: false

logging:
  level: "info"
  format: "json"
  file: "/var/log/gamepanel/agent.log"

scripts:
  timeout: 5m
  allowed_interpreters:
    - "/bin/bash"
    - "/bin/sh"
  sandbox:
    drop_capabilities: true
    no_new_privileges: true
    read_only_paths:
      - "/usr"
      - "/lib"
      - "/lib64"
EOF

  chown "$user:$user" "$config"
  chmod 0640 "$config"
}

gp_node_update_token_in_config() {
  local token="$1"
  local config="/opt/gamepanel/agent/config.yaml"
  local user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  [[ -z "$token" || "$token" == "null" ]] && return 1
  sed -i "s|^  token:.*|  token: \"${token}\"|" "$config"
  chown "$user:$user" "$config"
  gp_merge_env_key GAMEPANEL_NODE_TOKEN "$token"
}

gp_node_systemd() {
  gp_systemd_write_unit /etc/systemd/system/gamepanel-agent.service \
    "$(gp_systemd_node_agent_unit)"
  gp_systemd_enable_now gamepanel-agent.service
}

gp_node_prechecks() {
  gp_system_has_systemd || gp_die "systemd erforderlich für Game Nodes"
  systemctl is-system-running --quiet || gp_warn "System bootet noch oder degraded state"
  gp_os_check_kernel_modules
  gp_os_check_cgroup_v2 || [[ "${GAMEPANEL_NODE_SKIP_CGROUP_CHECK:-no}" == "yes" ]] || gp_die "cgroups v2 erforderlich"
  gp_info "Kernel: $(gp_os_kernel_version)"
}

gp_node_test_image_server() {
  local host user key
  host="$(gp_get_env IMAGE_SERVER_HOST "")"
  host="$(gp_get_env GAMEPANEL_IMAGE_SERVER_HOST "$host")"
  user="$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  key="$(gp_get_env GAMEPANEL_IMAGE_SERVER_SSH_KEY /etc/gamepanel/keys/image-server)"
  [[ -n "$host" && "$host" != "pending" ]] || { gp_info "Kein Image-Server — Test übersprungen"; return 0; }
  [[ -f "$key" ]] || { gp_warn "SFTP-Key fehlt — Test übersprungen"; return 0; }

  gp_info "Teste SFTP zu ${user}@${host}…"
  local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -i "$key")
  if ssh "${ssh_opts[@]}" "${user}@${host}" exit 0 2>/dev/null; then
    gp_ok "Image-Server erreichbar"
    return 0
  fi
  gp_warn "Image-Server nicht erreichbar (${user}@${host}) — später prüfen"
  return 0
}

gp_node_claim_deploy() {
  local panel_url deploy_token hostname ip resp tls_flags=() tls_insecure=false
  panel_url="$(gp_get_env GAMEPANEL_PANEL_URL "")"
  deploy_token="$(gp_get_env GAMEPANEL_DEPLOY_TOKEN "")"
  hostname="$(gp_get_env GAMEPANEL_NODE_HOSTNAME "$(hostname -s)")"
  ip="$(gp_get_env GAMEPANEL_NODE_IP "")"
  [[ -n "$ip" ]] || ip="$(gp_detect_primary_ip 2>/dev/null || hostname -I | awk '{print $1}')"

  [[ -n "$panel_url" ]] || gp_die "GAMEPANEL_PANEL_URL fehlt"
  [[ -n "$deploy_token" ]] || return 1

  [[ "$(gp_get_env GAMEPANEL_PANEL_TLS_INSECURE no)" == "yes" ]] && tls_flags+=(-k) && tls_insecure=true

  local payload agent_ver config_path user
  agent_ver="$(gp_node_agent_version)"
  user="${GAMEPANEL_NODE_USER:-gamepanel-node}"
  config_path="/opt/gamepanel/agent/config.yaml"

  payload=$(jq -n \
    --arg deploy_token "$deploy_token" \
    --arg hostname "$hostname" \
    --arg ip "$ip" \
    --arg agent_version "$agent_ver" \
    --argjson tls_insecure "$tls_insecure" \
    '{deploy_token:$deploy_token, hostname:$hostname, ip_address:$ip, agent_version:$agent_version, tls_insecure:$tls_insecure}')

  gp_info "Claim Node: ${panel_url%/}/api/install/node/claim"
  if ! resp=$(curl -fsS "${tls_flags[@]}" -X POST "${panel_url%/}/api/install/node/claim" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1); then
    gp_die "Node-Claim fehlgeschlagen: ${resp}"
  fi

  local token yaml key host
  token="$(echo "$resp" | jq -r '.token // empty')"
  yaml="$(echo "$resp" | jq -r '.config_yaml // empty')"
  key="$(echo "$resp" | jq -r '.image_server.private_key // empty')"
  host="$(echo "$resp" | jq -r '.image_server.host // empty')"

  [[ -n "$token" ]] || gp_die "Kein agent token in Claim-Antwort"
  [[ -n "$yaml" ]] || gp_die "Kein config_yaml in Claim-Antwort"

  # MariaDB-Passwort in YAML einsetzen
  local mysql_pass
  mysql_pass="$(gp_get_env GAMEPANEL_NODE_MYSQL_PASSWORD "")"
  if [[ -n "$mysql_pass" ]]; then
    yaml="$(printf '%s\n' "$yaml" | sed "s|__MYSQL_PASSWORD__|${mysql_pass}|g")"
  else
    yaml="$(printf '%s\n' "$yaml" | sed 's|__MYSQL_PASSWORD__||g')"
  fi

  printf '%s\n' "$yaml" > "$config_path"
  chown "$user:$user" "$config_path"
  chmod 0640 "$config_path"
  gp_merge_env_key GAMEPANEL_NODE_TOKEN "$token"
  [[ -n "$host" && "$host" != "null" ]] && gp_set_cfg IMAGE_SERVER_HOST "$host"
  gp_node_write_sftp_key_from_claim "$key"

  cat > "${GAMEPANEL_ETC}/node.env" <<ENVEOF
GAMEPANEL_PANEL_URL=${panel_url}
GAMEPANEL_NODE_TOKEN=${token}
GAMEPANEL_AGENT_CONFIG=${config_path}
GAMEPANEL_NODE_MYSQL_PASSWORD=${mysql_pass}
GAMEPANEL_PANEL_TLS_INSECURE=$(gp_get_env GAMEPANEL_PANEL_TLS_INSECURE no)
ENVEOF
  chmod 0640 "${GAMEPANEL_ETC}/node.env"
  gp_ok "Node via Deploy-Token geclaimt"
  return 0
}

gp_node_register() {
  # Primär: Deploy-Token Claim
  if [[ -n "$(gp_get_env GAMEPANEL_DEPLOY_TOKEN "")" ]]; then
    gp_node_claim_deploy
    return 0
  fi

  local panel_url setup_token name hostname ip resp token tls_flags=()
  panel_url="$(gp_get_env GAMEPANEL_PANEL_URL "")"
  setup_token="$(gp_get_env GAMEPANEL_SETUP_TOKEN "")"
  name="$(gp_get_env GAMEPANEL_NODE_NAME "$(hostname -f)")"
  hostname="$(gp_get_env GAMEPANEL_NODE_HOSTNAME "$(hostname -s)")"
  ip="$(gp_get_env GAMEPANEL_NODE_IP "")"
  [[ -n "$ip" ]] || ip="$(gp_detect_primary_ip 2>/dev/null || hostname -I | awk '{print $1}')"

  [[ -n "$panel_url" ]] || gp_die "GAMEPANEL_PANEL_URL fehlt"
  [[ -n "$setup_token" ]] || gp_die "GAMEPANEL_SETUP_TOKEN oder --deploy-token fehlt"

  if [[ -n "$(gp_get_env GAMEPANEL_NODE_TOKEN "")" ]]; then
    gp_info "Node-Token schon gesetzt — Registrierung übersprungen"
    return 0
  fi

  [[ "$(gp_get_env GAMEPANEL_PANEL_TLS_INSECURE no)" == "yes" ]] && tls_flags+=(-k)

  local payload agent_ver
  agent_ver="$(gp_node_agent_version)"
  payload=$(jq -n \
    --arg name "$name" \
    --arg hostname "$hostname" \
    --arg ip "$ip" \
    --arg agent_version "$agent_ver" \
    --arg setup_token "$setup_token" \
    '{name:$name, hostname:$hostname, ip_address:$ip, agent_version:$agent_version, setup_token:$setup_token}')

  gp_info "Registriere Node (legacy): ${panel_url%/}/api/node/register"
  if ! resp=$(curl -fsS "${tls_flags[@]}" -X POST "${panel_url%/}/api/node/register" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1); then
    gp_die "Panel-Registrierung fehlgeschlagen: ${resp}"
  fi

  token="$(echo "$resp" | jq -r '.token // empty')"
  [[ -n "$token" ]] || gp_die "Kein token in Antwort: ${resp}"
  gp_node_update_token_in_config "$token"
  gp_ok "Node registriert"
}

gp_install_node() {
  gp_log_info "Start Game-Node Installation — production deps"
  gp_os_require_supported
  gp_node_prechecks
  gp_run_step node_user "Node-Benutzer & Verzeichnisse" gp_node_create_user
  gp_run_step node_deps "Runtimes (lib32, Java, MariaDB, Tools)" gp_node_install_deps
  gp_run_step node_mariadb "MariaDB härten + Agent-User" gp_node_configure_mariadb
  gp_run_step node_steam "SteamCMD" gp_node_install_steamcmd
  gp_run_step node_verify "Runtime-Verifikation" gp_node_verify_runtimes
  gp_run_step node_agent "GamePanel Agent" gp_node_install_agent

  if [[ -n "$(gp_get_env GAMEPANEL_DEPLOY_TOKEN "")" ]]; then
    gp_run_step node_claim "Panel Claim (Deploy-Token)" gp_node_claim_deploy
  else
    gp_run_step node_image_key "SFTP-Schlüssel (Legacy)" gp_node_pull_image_key
    gp_run_step node_config "Agent config.yaml" gp_node_write_config
    gp_run_step node_register "Panel-Registrierung (Legacy)" gp_node_register
  fi

  gp_run_step node_systemd "Agent systemd Unit" gp_node_systemd
  gp_run_step node_sftp_test "Image-Server Erreichbarkeit" gp_node_test_image_server || true
  gp_fw_setup_node
  gp_log_info "Game-Node fertig. Prüfen: systemctl status gamepanel-agent"
  gp_msg ""
  gp_msg "  Java:     $(command -v java) ($(java -version 2>&1 | head -1))"
  gp_msg "  SteamCMD: /opt/gamepanel/steamcmd/steamcmd.sh"
  gp_msg "  MariaDB:  127.0.0.1 (User gamepanel-agent)"
  gp_msg "  Agent:    systemctl status gamepanel-agent"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || true
  gp_install_node
fi
