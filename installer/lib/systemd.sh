#!/usr/bin/env bash
# GamePanel Installer — systemd
set -euo pipefail

gp_systemd_enable_now() {
  local unit="$1"
  if ! gp_system_has_systemd; then
    gp_die "systemd wird benötigt, ist aber nicht aktiv."
  fi
  systemctl daemon-reload
  systemctl enable "$unit" >/dev/null 2>&1 || true
  systemctl start "$unit"
  systemctl is-active --quiet "$unit" || gp_die "Unit ${unit} nicht aktiv"
}

gp_systemd_restart() {
  local unit="$1"
  systemctl restart "$unit"
}

gp_systemd_stop_disable() {
  local unit="$1"
  systemctl stop "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
}

gp_systemd_write_unit() {
  local path="$1"
  local content="$2"
  echo "$content" > "$path"
  chmod 0644 "$path"
  systemctl daemon-reload
}

gp_systemd_node_agent_unit() {
  local bin="${GAMEPANEL_NODE_AGENT_BIN:-/usr/local/bin/gamepanel-agent}"
  local config="${GAMEPANEL_AGENT_CONFIG:-/opt/gamepanel/agent/config.yaml}"
  local env_file="${GAMEPANEL_ETC}/node.env"
  # Agent braucht root für useradd + systemctl (wie Pterodactyl Wings)
  cat <<EOF
[Unit]
Description=GamePanel Game Node Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=-${env_file}
ExecStart=${bin} run --config ${config}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

gp_systemd_panel_worker_unit() {
  local user="${GAMEPANEL_DEPLOY_USER:-gamepanel}"
  local dir="${GAMEPANEL_PANEL_DIR:-/opt/gamepanel}"
  cat <<EOF
[Unit]
Description=GamePanel Queue Worker (Host systemd, optional)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=${user}
WorkingDirectory=${dir}
ExecStart=/usr/bin/docker compose -f ${dir}/docker-compose.yml exec -T backend php artisan queue:work --sleep=3 --tries=3 --max-time=3600
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

# Alias für Abwärtskompatibilität
gp_systemd_worker_unit() {
  gp_systemd_panel_worker_unit
}
