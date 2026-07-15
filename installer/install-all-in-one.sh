#!/usr/bin/env bash
# Standalone: Panel + DB + Redis + Image Server + optional Node
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${INSTALLER_DIR}/lib/common.sh"
source "${INSTALLER_DIR}/lib/logging.sh"
source "${INSTALLER_DIR}/lib/prompts.sh"

gp_install_standalone() {
  gp_log_info "Standalone-Installation (All-in-One)"
  export GAMEPANEL_DB_EXTERNAL=no
  export GAMEPANEL_REDIS_HOST=redis
  export IMAGE_SERVER_ROOT="${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
  export IMAGE_SERVER_HOST="${IMAGE_SERVER_HOST:-127.0.0.1}"
  bash "${INSTALLER_DIR}/install-panel.sh"
  bash "${INSTALLER_DIR}/install-image-server.sh"
  if [[ "$(gp_get_env STANDALONE_INSTALL_NODE no)" == "yes" ]]; then
    export GAMEPANEL_PANEL_URL="${GAMEPANEL_PANEL_URL:-https://127.0.0.1:$(gp_get_env HTTPS_PORT 443)}"
    bash "${INSTALLER_DIR}/install-node.sh"
  fi
  gp_ok "Standalone-Installation abgeschlossen"
}

gp_install_database_role() {
  gp_log_info "Dedizierter Database-Server"
  source "${INSTALLER_DIR}/lib/os.sh"
  gp_os_require_supported
  gp_apt_install gnupg curl ca-certificates
  # PostgreSQL 16 aus PGDG
  install -d /usr/share/postgresql-common/pgdg
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo ${VERSION_CODENAME}-pgdg) main" \
    > /etc/apt/sources.list.d/pgdg.list
  apt-get update -qq
  gp_apt_install postgresql-16
  local db user pass
  db="$(gp_get_env POSTGRES_DB gamepanel)"
  user="$(gp_get_env POSTGRES_USER gamepanel)"
  pass="$(gp_get_env POSTGRES_PASSWORD "$(gp_random_secret 32)")"
  sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${user}'" | grep -q 1 \
    || sudo -u postgres psql -c "CREATE USER ${user} WITH PASSWORD '${pass}';"
  sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 \
    || sudo -u postgres psql -c "CREATE DATABASE ${db} OWNER ${user};"
  gp_merge_env_key POSTGRES_PASSWORD "$pass"
  echo "host ${db} ${user} 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
  echo "listen_addresses = '*'" >> /etc/postgresql/16/main/postgresql.conf
  systemctl restart postgresql
  source "${INSTALLER_DIR}/lib/firewall.sh"
  gp_fw_allow_port 5432 tcp "postgresql"
  gp_set_marker database_server
  gp_ok "PostgreSQL 16 bereit"
}

gp_install_worker_role() {
  gp_log_info "Worker-Rolle"
  source "${INSTALLER_DIR}/lib/systemd.sh"
  source "${INSTALLER_DIR}/lib/docker.sh"
  gp_docker_install_packages || true
  gp_systemd_write_unit /etc/systemd/system/gamepanel-worker.service "$(gp_systemd_worker_unit)"
  gp_systemd_enable_now gamepanel-worker.service
  gp_set_marker worker_server
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || true
  role="${1:-standalone}"
  case "$role" in
    standalone) gp_install_standalone ;;
    database) gp_install_database_role ;;
    worker) gp_install_worker_role ;;
    *) gp_die "Unbekannte Rolle für all-in-one: $role" ;;
  esac
fi
