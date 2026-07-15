#!/usr/bin/env bash
set -euo pipefail

cd /var/www/html

if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
fi

# Named volume kann alte packages.php mit Dev-Providern enthalten
rm -f bootstrap/cache/packages.php bootstrap/cache/services.php
php artisan package:discover --ansi --no-interaction >/dev/null 2>&1 || true

if ! grep -q '^APP_KEY=base64:' .env 2>/dev/null; then
  if [[ -z "${APP_KEY:-}" ]]; then
    php artisan key:generate --force || true
  fi
fi

# Warte kurz auf DB (Compose healthcheck sollte greifen)
for i in $(seq 1 30); do
  if php artisan db:show >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

php artisan migrate --force --no-interaction || true

if [[ "${RUN_SEED:-false}" == "true" ]]; then
  php artisan db:seed --force --no-interaction || true
fi

exec "$@"
