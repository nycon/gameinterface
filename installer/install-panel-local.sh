#!/usr/bin/env bash
# GamePanel — Panel lokal starten (Docker Compose im Repo)
# Inkl. SSL-Zertifikat erzeugen und in Nginx einbinden.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${INSTALLER_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/docker.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/ssl.sh"

gp_panel_local_env() {
  local env_file="${ROOT}/.env"
  local db_pass redis_pass app_key
  local http_port https_port domain

  http_port="${HTTP_PORT:-8080}"
  https_port="${HTTPS_PORT:-8443}"
  domain="${PANEL_DOMAIN:-localhost}"

  if [[ -f "$env_file" && "${GAMEPANEL_PANEL_OVERWRITE_ENV:-no}" != "yes" ]]; then
    gp_info ".env existiert — behalte vorhandene Datei"
  else
    cp "${ROOT}/.env.example" "$env_file"
  fi

  db_pass="$(grep -E '^POSTGRES_PASSWORD=' "$env_file" | cut -d= -f2- || true)"
  if [[ -z "$db_pass" || "$db_pass" == "changeme_generate_strong_secret" ]]; then
    db_pass="$(gp_random_secret 24)"
  fi
  redis_pass="$(grep -E '^REDIS_PASSWORD=' "$env_file" | cut -d= -f2- || true)"
  if [[ -z "$redis_pass" || "$redis_pass" == "changeme_generate_strong_secret" ]]; then
    redis_pass="$(gp_random_secret 24)"
  fi
  app_key="$(grep -E '^APP_KEY=' "$env_file" | cut -d= -f2- || true)"
  if [[ -z "$app_key" ]]; then
    app_key="base64:$(openssl rand -base64 32)"
  fi

  local admin_email admin_pass
  admin_email="${GAMEPANEL_ADMIN_EMAIL:-admin@gamepanel.local}"
  admin_pass="${GAMEPANEL_ADMIN_PASSWORD:-ChangeMe!2026}"

  gp_env_set() {
    local key="$1" value="$2" file="$3"
    local tmp
    tmp="$(mktemp)"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
      grep -v "^${key}=" "$file" > "$tmp" || true
      printf '%s=%s\n' "$key" "$value" >> "$tmp"
      mv "$tmp" "$file"
    else
      rm -f "$tmp"
      printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
  }

  gp_env_set APP_NAME GamePanel "$env_file"
  gp_env_set APP_ENV local "$env_file"
  gp_env_set APP_DEBUG true "$env_file"
  gp_env_set APP_KEY "$app_key" "$env_file"
  gp_env_set APP_URL "https://127.0.0.1:${https_port}" "$env_file"
  gp_env_set PANEL_DOMAIN "$domain" "$env_file"
  gp_env_set SSL_MODE "${SSL_MODE:-selfsigned}" "$env_file"
  gp_env_set SSL_EMAIL "$admin_email" "$env_file"
  gp_env_set BROADCAST_CONNECTION reverb "$env_file"
  gp_env_set REVERB_APP_ID gamepanel "$env_file"
  gp_env_set REVERB_APP_KEY gamepanel-key "$env_file"
  gp_env_set REVERB_APP_SECRET gamepanel-secret "$env_file"
  gp_env_set REVERB_HOST localhost "$env_file"
  gp_env_set REVERB_PORT 8080 "$env_file"
  gp_env_set REVERB_SCHEME http "$env_file"
  gp_env_set VITE_REVERB_APP_KEY gamepanel-key "$env_file"
  gp_env_set VITE_REVERB_HOST 127.0.0.1 "$env_file"
  gp_env_set VITE_REVERB_PORT "$https_port" "$env_file"
  gp_env_set VITE_REVERB_SCHEME https "$env_file"
  gp_env_set HTTP_PORT "$http_port" "$env_file"
  gp_env_set HTTPS_PORT "$https_port" "$env_file"
  gp_env_set POSTGRES_DB gamepanel "$env_file"
  gp_env_set POSTGRES_USER gamepanel "$env_file"
  gp_env_set POSTGRES_PASSWORD "$db_pass" "$env_file"
  gp_env_set REDIS_PASSWORD "$redis_pass" "$env_file"
  gp_env_set DB_CONNECTION pgsql "$env_file"
  gp_env_set DB_HOST postgres "$env_file"
  gp_env_set DB_PORT 5432 "$env_file"
  gp_env_set DB_DATABASE gamepanel "$env_file"
  gp_env_set DB_USERNAME gamepanel "$env_file"
  gp_env_set DB_PASSWORD "$db_pass" "$env_file"
  gp_env_set REDIS_HOST redis "$env_file"
  gp_env_set CACHE_STORE redis "$env_file"
  gp_env_set SESSION_DRIVER redis "$env_file"
  gp_env_set QUEUE_CONNECTION redis "$env_file"
  gp_env_set RUN_SEED true "$env_file"
  gp_env_set GAMEPANEL_ADMIN_EMAIL "$admin_email" "$env_file"
  gp_env_set GAMEPANEL_ADMIN_PASSWORD "$admin_pass" "$env_file"

  export GAMEPANEL_ADMIN_EMAIL="$admin_email"
  export GAMEPANEL_ADMIN_PASSWORD="$admin_pass"
  export PANEL_DOMAIN="$domain"
  export SSL_MODE="${SSL_MODE:-selfsigned}"
  gp_ok ".env bereit unter ${env_file}"
}

gp_panel_local_ssl() {
  export GAMEPANEL_SSL_DIR="${ROOT}/deploy/nginx/certs"
  export PANEL_DOMAIN="${PANEL_DOMAIN:-localhost}"
  export SSL_MODE="${SSL_MODE:-selfsigned}"
  gp_ssl_ensure
}

gp_panel_local_compose() {
  export GAMEPANEL_USE_PROD_COMPOSE=no
  [[ -f "${ROOT}/deploy/nginx/certs/fullchain.pem" ]] \
    || gp_die "SSL-Zertifikat fehlt — gp_panel_local_ssl zuerst ausführen"
  gp_info "Baue und starte Panel-Stack (docker compose)…"
  (cd "$ROOT" && docker compose -f docker-compose.yml build)
  (cd "$ROOT" && docker compose -f docker-compose.yml up -d)
}

gp_panel_local_wait() {
  local http_port https_port i
  http_port="$(grep -E '^HTTP_PORT=' "${ROOT}/.env" | cut -d= -f2- || echo 8080)"
  https_port="$(grep -E '^HTTPS_PORT=' "${ROOT}/.env" | cut -d= -f2- || echo 8443)"
  [[ -n "$http_port" ]] || http_port=8080
  [[ -n "$https_port" ]] || https_port=8443
  gp_info "Warte auf Panel-Health (HTTP :${http_port} / HTTPS :${https_port})…"
  for i in $(seq 1 60); do
    if curl -fsS --max-time 3 "http://127.0.0.1:${http_port}/api/health" >/dev/null 2>&1; then
      gp_ok "API healthy (HTTP)"
      return 0
    fi
    if curl -fkSs --max-time 3 "https://127.0.0.1:${https_port}/api/health" >/dev/null 2>&1; then
      gp_ok "API healthy (HTTPS)"
      return 0
    fi
    if (cd "$ROOT" && docker compose exec -T backend php -r "echo @file_get_contents('http://127.0.0.1:8000/api/health') ?: '';" 2>/dev/null | grep -q ok); then
      gp_ok "Backend healthy (Proxy ggf. noch warm)"
      return 0
    fi
    sleep 5
  done
  gp_die "Panel startete nicht. Logs: cd ${ROOT} && docker compose logs --tail=80"
}

gp_panel_local_migrate() {
  gp_info "Migrationen…"
  (cd "$ROOT" && docker compose exec -T backend php artisan migrate --force --no-interaction)
  if [[ "${RUN_SEED:-true}" == "true" ]]; then
    (cd "$ROOT" && docker compose exec -T backend php artisan db:seed --force --no-interaction) || true
  fi
  local email pass
  email="${GAMEPANEL_ADMIN_EMAIL:-admin@gamepanel.local}"
  pass="${GAMEPANEL_ADMIN_PASSWORD:-ChangeMe!2026}"
  (cd "$ROOT" && docker compose exec -T backend php artisan gamepanel:admin-create \
    --email="$email" --password="$pass" --name=Administrator) || true
  (cd "$ROOT" && docker compose exec -T backend php artisan gamepanel:setup-token-create) || true
}

gp_install_panel_local() {
  gp_log_info "Panel Local Install (Docker Compose + SSL)"
  if ! command -v docker >/dev/null 2>&1; then
    gp_die "Docker fehlt. Bitte Docker Desktop / Engine installieren."
  fi
  if ! docker info >/dev/null 2>&1; then
    gp_die "Docker läuft nicht. Bitte Docker starten und erneut versuchen."
  fi
  if ! docker compose version >/dev/null 2>&1; then
    gp_die "Docker Compose Plugin fehlt (docker compose)."
  fi
  [[ -f "${ROOT}/docker-compose.yml" ]] || gp_die "Kein docker-compose.yml in ${ROOT}"

  gp_panel_local_env
  gp_panel_local_ssl
  gp_panel_local_compose
  gp_panel_local_wait
  gp_panel_local_migrate

  local http_port https_port
  http_port="$(grep -E '^HTTP_PORT=' "${ROOT}/.env" | cut -d= -f2- || echo 8080)"
  https_port="$(grep -E '^HTTPS_PORT=' "${ROOT}/.env" | cut -d= -f2- || echo 8443)"
  cat <<EOF

========================================
  GamePanel ist bereit (Nginx + SSL)
========================================
  HTTPS:  https://127.0.0.1:${https_port}/
  HTTP:   http://127.0.0.1:${http_port}/
  API:    https://127.0.0.1:${https_port}/api/health

  Login:  ${GAMEPANEL_ADMIN_EMAIL:-admin@gamepanel.local}
  Pass:   ${GAMEPANEL_ADMIN_PASSWORD:-ChangeMe!2026}

  SSL:    ${ROOT}/deploy/nginx/certs/  (self-signed → Browser-Warnung normal)
  Mode:   ${SSL_MODE:-selfsigned}

  Logs:   cd ${ROOT} && docker compose logs -f
  Stop:   cd ${ROOT} && docker compose down
========================================
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_log_init 2>/dev/null || true
  gp_install_panel_local
fi
