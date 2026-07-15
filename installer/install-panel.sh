#!/usr/bin/env bash
# GamePanel — Panel-Server Installation (VM1)
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/os.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/docker.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/systemd.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/firewall.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/ssl.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/config_collect.sh"

: "${GAMEPANEL_SOURCE_DIR:=$(cd "${INSTALLER_DIR}/.." && pwd)}"
: "${GAMEPANEL_PANEL_DIR:=/opt/gamepanel}"
: "${GAMEPANEL_DEPLOY_USER:=gamepanel}"
: "${GAMEPANEL_SSL_DIR:=${GAMEPANEL_PANEL_DIR}/deploy/nginx/certs}"

gp_panel_create_user() {
  local user="${GAMEPANEL_DEPLOY_USER}"
  if ! id "$user" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /opt/gamepanel --shell /bin/bash "$user"
  fi
  install -d -m 0755 /opt/gamepanel
  chown "$user:$user" /opt/gamepanel
}

gp_panel_resolve_source() {
  local src="${GAMEPANEL_SOURCE_DIR}"
  src="$(cd "$src" && pwd)"
  if [[ ! -f "${src}/docker-compose.yml" ]]; then
    gp_die "GAMEPANEL_SOURCE_DIR enthält kein docker-compose.yml: ${src}"
  fi
  echo "$src"
}

gp_panel_sync_source() {
  local src dest user
  src="$(gp_panel_resolve_source)"
  dest="${GAMEPANEL_PANEL_DIR}"
  user="${GAMEPANEL_DEPLOY_USER}"

  local src_real dest_parent
  src_real="$(realpath "$src")"
  dest_parent="$(dirname "$dest")"
  install -d -m 0755 "$dest_parent"

  if [[ -e "$dest" ]] && [[ "$(realpath "$dest" 2>/dev/null || true)" == "$src_real" ]]; then
    gp_info "Panel-Verzeichnis ist bereits das Quell-Repository: ${dest}"
    return 0
  fi

  if [[ "${GAMEPANEL_PANEL_SYMLINK:-no}" == "yes" ]]; then
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      gp_die "${dest} existiert und ist kein Symlink — entfernen oder GAMEPANEL_PANEL_SYMLINK=no setzen."
    fi
    ln -sfn "$src_real" "$dest"
    gp_ok "Symlink: ${dest} -> ${src_real}"
    return 0
  fi

  gp_info "Synchronisiere Panel-Quellcode nach ${dest}…"
  gp_apt_install rsync
  rsync -a \
    --exclude '.git/' \
    --exclude 'node_modules/' \
    --exclude 'frontend/node_modules/' \
    --exclude 'backend/vendor/' \
    --exclude '.env' \
    "${src}/" "${dest}/"
  chown -R "${user}:${user}" "$dest"
}

gp_panel_write_env() {
  local dir="${GAMEPANEL_PANEL_DIR}"
  local env_file="${dir}/.env"
  local template="${dir}/.env.example"
  local user="${GAMEPANEL_DEPLOY_USER}"

  local db_pass redis_pass app_key panel_domain app_url
  db_pass="$(gp_get_env POSTGRES_PASSWORD "")"
  [[ -n "$db_pass" ]] || db_pass="$(gp_random_secret 32)"
  redis_pass="$(gp_get_env REDIS_PASSWORD "")"
  [[ -n "$redis_pass" ]] || redis_pass="$(gp_random_secret 32)"
  app_key="$(gp_get_env APP_KEY "")"
  if [[ -z "$app_key" ]]; then
    app_key="base64:$(openssl rand -base64 32 2>/dev/null || gp_random_secret 44)"
  fi

  panel_domain="$(gp_get_env PANEL_DOMAIN "")"
  [[ -n "$panel_domain" ]] || panel_domain="$(gp_get_env GAMEPANEL_PANEL_DOMAIN "")"
  [[ -n "$panel_domain" ]] || panel_domain="$(echo "$(gp_get_env GAMEPANEL_URL https://panel.example.com)" | sed -E 's#^https?://##; s#/.*##')"

  app_url="$(gp_get_env APP_URL "")"
  [[ -n "$app_url" ]] || app_url="$(gp_get_env GAMEPANEL_URL "https://${panel_domain}")"

  if [[ -f "$env_file" && "${GAMEPANEL_PANEL_OVERWRITE_ENV:-no}" != "yes" ]]; then
    gp_info ".env existiert bereits — überspringe (GAMEPANEL_PANEL_OVERWRITE_ENV=yes zum Überschreiben)"
    return 0
  fi

  if [[ -f "$template" ]]; then
    cp "$template" "$env_file"
  else
    touch "$env_file"
  fi

  gp_panel_env_set "$env_file" COMPOSE_PROJECT_NAME "$(gp_get_env COMPOSE_PROJECT_NAME gamepanel)"
  gp_panel_env_set "$env_file" APP_NAME GamePanel
  gp_panel_env_set "$env_file" APP_ENV production
  gp_panel_env_set "$env_file" APP_DEBUG false
  gp_panel_env_set "$env_file" APP_KEY "$app_key"
  gp_panel_env_set "$env_file" APP_URL "$app_url"
  gp_panel_env_set "$env_file" PANEL_DOMAIN "$panel_domain"
  gp_panel_env_set "$env_file" SSL_MODE "$(gp_get_env SSL_MODE selfsigned)"
  gp_panel_env_set "$env_file" SSL_EMAIL "$(gp_get_env SSL_EMAIL "$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@example.com)")"
  gp_panel_env_set "$env_file" ACME_EMAIL "$(gp_get_env ACME_EMAIL "$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@example.com)")"
  gp_panel_env_set "$env_file" GAMEPANEL_USE_PROD_COMPOSE "$(gp_get_env GAMEPANEL_USE_PROD_COMPOSE no)"

  # APP_URL auf HTTPS ausrichten
  if [[ "$app_url" == http://* ]]; then
    app_url="https://${panel_domain}"
    gp_panel_env_set "$env_file" APP_URL "$app_url"
  fi
  gp_panel_env_set "$env_file" POSTGRES_DB "$(gp_get_env POSTGRES_DB gamepanel)"
  gp_panel_env_set "$env_file" POSTGRES_USER "$(gp_get_env POSTGRES_USER gamepanel)"
  gp_panel_env_set "$env_file" POSTGRES_PASSWORD "$db_pass"
  gp_panel_env_set "$env_file" REDIS_PASSWORD "$redis_pass"
  gp_panel_env_set "$env_file" DB_CONNECTION pgsql
  gp_panel_env_set "$env_file" DB_HOST "$(gp_get_env DB_HOST postgres)"
  gp_panel_env_set "$env_file" DB_PORT "$(gp_get_env DB_PORT 5432)"
  gp_panel_env_set "$env_file" DB_DATABASE "$(gp_get_env POSTGRES_DB gamepanel)"
  gp_panel_env_set "$env_file" DB_USERNAME "$(gp_get_env POSTGRES_USER gamepanel)"
  gp_panel_env_set "$env_file" DB_PASSWORD "$db_pass"
  gp_panel_env_set "$env_file" REDIS_HOST "$(gp_get_env REDIS_HOST redis)"
  gp_panel_env_set "$env_file" CACHE_STORE redis
  gp_panel_env_set "$env_file" SESSION_DRIVER redis
  gp_panel_env_set "$env_file" QUEUE_CONNECTION redis
  gp_panel_env_set "$env_file" LOG_LEVEL info
  gp_panel_env_set "$env_file" RUN_SEED "$(gp_get_env RUN_SEED true)"
  gp_panel_env_set "$env_file" BACKEND_IMAGE "$(gp_get_env BACKEND_IMAGE gamepanel-backend:local)"
  gp_panel_env_set "$env_file" FRONTEND_IMAGE "$(gp_get_env FRONTEND_IMAGE gamepanel-frontend:local)"
  gp_panel_env_set "$env_file" HTTP_PORT "$(gp_get_env HTTP_PORT 80)"
  gp_panel_env_set "$env_file" HTTPS_PORT "$(gp_get_env HTTPS_PORT 443)"
  gp_panel_env_set "$env_file" BROADCAST_CONNECTION reverb
  gp_panel_env_set "$env_file" REVERB_APP_ID "$(gp_get_env REVERB_APP_ID gamepanel)"
  gp_panel_env_set "$env_file" REVERB_APP_KEY "$(gp_get_env REVERB_APP_KEY gamepanel-key)"
  gp_panel_env_set "$env_file" REVERB_APP_SECRET "$(gp_get_env REVERB_APP_SECRET "$(gp_random_secret 32)")"
  gp_panel_env_set "$env_file" GAMEPANEL_ADMIN_EMAIL "$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@gamepanel.local)"
  gp_panel_env_set "$env_file" GAMEPANEL_ADMIN_PASSWORD "$(gp_get_env GAMEPANEL_ADMIN_PASSWORD "")"

  local img_host img_user
  img_host="$(gp_get_env IMAGE_SERVER_HOST "")"
  img_host="$(gp_get_env GAMEPANEL_IMAGE_SERVER_HOST "$img_host")"
  [[ -n "$img_host" ]] && gp_panel_env_set "$env_file" GAMEPANEL_IMAGE_SERVER_HOST "$img_host"
  img_user="$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  gp_panel_env_set "$env_file" GAMEPANEL_IMAGE_SERVER_USER "$img_user"
  gp_panel_env_set "$env_file" GAMEPANEL_IMAGE_SERVER_PORT "$(gp_get_env GAMEPANEL_IMAGE_SERVER_PORT 22)"
  gp_panel_env_set "$env_file" GAMEPANEL_IMAGE_SERVER_PROTOCOL sftp

  chmod 0640 "$env_file"
  chown "${user}:${user}" "$env_file"
  gp_merge_env_key POSTGRES_PASSWORD "$db_pass"
  gp_merge_env_key REDIS_PASSWORD "$redis_pass"
  gp_merge_env_key APP_KEY "$app_key"
  gp_merge_env_key PANEL_DOMAIN "$panel_domain"
  gp_merge_env_key APP_URL "$app_url"
}

gp_panel_env_set() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

gp_panel_wait_health() {
  local dir="${GAMEPANEL_PANEL_DIR}"
  local http_port https_port max i
  http_port="$(gp_get_env HTTP_PORT 80)"
  https_port="$(gp_get_env HTTPS_PORT 443)"
  max="${GAMEPANEL_HEALTH_WAIT_SEC:-300}"
  gp_info "Warte auf API-Health (max ${max}s)…"
  for ((i = 1; i <= max / 5; i++)); do
    if curl -fsS --max-time 5 "http://127.0.0.1:${http_port}/api/health" >/dev/null 2>&1; then
      gp_ok "Panel API ist healthy (HTTP)"
      return 0
    fi
    if curl -fkSs --max-time 5 "https://127.0.0.1:${https_port}/api/health" >/dev/null 2>&1; then
      gp_ok "Panel API ist healthy (HTTPS)"
      return 0
    fi
    if gp_docker_exec_backend "$dir" php -r "exit(@file_get_contents('http://127.0.0.1:8000/api/health')===false?1:0);" 2>/dev/null; then
      gp_ok "Backend-Container ist healthy"
      return 0
    fi
    sleep 5
  done
  gp_die "Health-Check /api/health nicht erfolgreich — Logs: docker compose logs backend proxy"
}

gp_panel_migrate() {
  local dir="${GAMEPANEL_PANEL_DIR}"
  gp_info "Datenbank-Migrationen ausführen…"
  gp_docker_exec_backend "$dir" php artisan migrate --force --no-interaction
  gp_ok "Migrationen abgeschlossen"
}

gp_panel_seed() {
  local dir="${GAMEPANEL_PANEL_DIR}"
  if [[ "$(gp_get_env RUN_SEED true)" != "true" ]]; then
    gp_info "RUN_SEED != true — Seeding übersprungen"
    return 0
  fi
  gp_info "Datenbank seeden…"
  gp_docker_exec_backend "$dir" php artisan db:seed --force --no-interaction || gp_warn "db:seed fehlgeschlagen oder leer"
}

gp_panel_admin_user() {
  local email pass name dir
  email="$(gp_get_env GAMEPANEL_ADMIN_EMAIL "")"
  pass="$(gp_get_env GAMEPANEL_ADMIN_PASSWORD "")"
  name="$(gp_get_env GAMEPANEL_ADMIN_NAME Administrator)"
  [[ -n "$email" && -n "$pass" ]] || return 0
  dir="${GAMEPANEL_PANEL_DIR}"
  gp_info "Admin-Benutzer anlegen…"
  if gp_docker_exec_backend "$dir" php artisan gamepanel:admin-create \
    --email="$email" --password="$pass" --name="$name" 2>/dev/null; then
    gp_ok "Admin-Benutzer erstellt: ${email}"
  else
    gp_warn "Admin-User konnte nicht automatisch erstellt werden — manuell anlegen."
  fi
}

gp_panel_setup_token() {
  local dir token out
  dir="${GAMEPANEL_PANEL_DIR}"
  token="$(gp_get_env GAMEPANEL_SETUP_TOKEN "")"
  if [[ -n "$token" ]]; then
    gp_info "GAMEPANEL_SETUP_TOKEN bereits gesetzt"
    return 0
  fi

  gp_info "Node Setup-Token erzeugen…"
  out="$(gp_docker_exec_backend "$dir" php artisan gamepanel:setup-token-create 2>/dev/null || true)"
  token="$(echo "$out" | grep -Eo '[A-Za-z0-9_-]{32,}' | tail -1 || true)"

  if [[ -z "$token" ]]; then
    token="$(gp_random_secret 48)"
    gp_warn "gamepanel:setup-token-create nicht verfügbar — Token via tinker setzen"
    gp_docker_exec_backend "$dir" php artisan tinker --execute="
\\App\\Models\\Setting::setValue('security.node_setup_token', '${token}');
" 2>/dev/null || gp_warn "Setting konnte nicht gesetzt werden — Token nur in installer.env"
  fi

  gp_merge_env_key GAMEPANEL_SETUP_TOKEN "$token"
  gp_ok "Setup-Token für Node-Registrierung (VM3): ${token}"
  gp_info "Token gespeichert in ${GAMEPANEL_ETC}/installer.env als GAMEPANEL_SETUP_TOKEN"
}

gp_panel_register_image_server() {
  local dir host user
  dir="${GAMEPANEL_PANEL_DIR}"
  host="$(gp_get_env IMAGE_SERVER_HOST "$(gp_get_env GAMEPANEL_IMAGE_SERVER_HOST "")")"
  user="$(gp_get_env IMAGE_SERVER_USER gamepanel-images)"
  [[ -n "$host" ]] || { gp_info "Kein --image-server-host — Image-Server-Eintrag übersprungen"; return 0; }

  gp_info "Registriere Image-Server in Panel-DB: ${host}…"
  if gp_docker_exec_backend "$dir" php artisan tinker --execute="
\$h='${host}'; \$u='${user}';
\$s=\\App\\Models\\ImageServer::query()->firstOrNew(['hostname'=>\$h]);
\$s->fill([
  'name'=>'Image Server',
  'protocol'=>'sftp',
  'port'=>22,
  'base_path'=>'/images',
  'username'=>\$u,
  'is_active'=>true,
]);
\$s->save();
echo 'ok:'.\$s->id;
" 2>/dev/null; then
    gp_ok "Image-Server in Panel hinterlegt (${host})"
  else
    gp_warn "Image-Server konnte nicht automatisch angelegt werden — im Admin-UI nachziehen"
  fi
}

gp_panel_ssl() {
  export GAMEPANEL_SSL_DIR="${GAMEPANEL_PANEL_DIR}/deploy/nginx/certs"
  export GAMEPANEL_PANEL_DIR
  gp_ssl_ensure
  chown -R "${GAMEPANEL_DEPLOY_USER}:${GAMEPANEL_DEPLOY_USER}" "${GAMEPANEL_SSL_DIR}" 2>/dev/null || true
}

_gp_panel_up() {
  local dir="${GAMEPANEL_PANEL_DIR}"
  [[ -f "${dir}/deploy/nginx/certs/fullchain.pem" ]] \
    || gp_die "SSL-Zertifikate fehlen unter ${dir}/deploy/nginx/certs — panel_ssl zuerst"
  gp_info "Docker Images bauen (backend/frontend)…"
  gp_docker_build "$dir"
  gp_docker_up "$dir"
}

gp_install_panel() {
  gp_log_info "Start Panel-Installation (VM1)"
  gp_os_require_supported
  gp_run_step panel_user "Panel-Systembenutzer" gp_panel_create_user
  gp_run_step panel_docker "Docker installieren" gp_docker_install_packages
  gp_run_step panel_docker_svc "Docker-Dienst aktivieren" gp_docker_configure_service
  gp_run_step panel_sync "Panel-Quellcode bereitstellen" gp_panel_sync_source
  gp_run_step panel_env "Panel .env erzeugen" gp_panel_write_env
  gp_run_step panel_ssl "SSL-Zertifikat erzeugen & einbinden" gp_panel_ssl
  gp_run_step panel_up "Container bauen & starten" "_gp_panel_up"
  gp_run_step panel_health "Health-Check" gp_panel_wait_health
  gp_run_step panel_migrate "Migrationen" gp_panel_migrate
  gp_run_step panel_seed "Datenbank seeden" gp_panel_seed
  gp_panel_admin_user
  gp_panel_setup_token
  gp_panel_register_image_server
  gp_fw_setup_panel "$(gp_get_env HTTP_PORT 80)" "$(gp_get_env HTTPS_PORT 443)"
  gp_write_node_join_file
  gp_log_info "Panel-Installation abgeschlossen — ${APP_URL:-$(gp_get_env APP_URL "")}"
  gp_ok "HTTPS aktiv — Zertifikate: ${GAMEPANEL_PANEL_DIR}/deploy/nginx/certs"
  gp_msg ""
  gp_msg "${COLOR_BOLD}=== Nächste Schritte (Panel-UI) ===${COLOR_RESET}"
  gp_msg "  1) Im Admin: Image-Server anlegen → Install-Befehl auf VM2 ausführen"
  gp_msg "  2) Im Admin: Node anlegen → Install-Befehl auf VM3 ausführen"
  gp_msg "  Panel: ${APP_URL:-$(gp_get_env APP_URL "")}"
  gp_msg ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || gp_load_config "${INSTALLER_DIR}/installer.env" 2>/dev/null || true
  gp_install_panel
fi
