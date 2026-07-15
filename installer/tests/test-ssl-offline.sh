#!/usr/bin/env bash
# Offline-Tests für SSL-Logik (kein certbot, kein Rate-Limit)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/installer/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT}/installer/lib/ssl.sh"

PASS=0
FAIL=0

assert() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name"
    FAIL=$((FAIL + 1))
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "${TMP}/live/gsp.g1-host.ch" "${TMP}/deploy"

# Create GamePanel self-signed in deploy FIRST
GAMEPANEL_SSL_DIR="${TMP}/deploy"
SSL_FORCE_REGEN=yes gp_ssl_generate_selfsigned "${TMP}/deploy" "gsp.g1-host.ch"
assert "deploy starts self-signed" gp_ssl_is_selfsigned_file "${TMP}/deploy/fullchain.pem"
assert "GamePanel cert is NOT detected as LE (no false positive on word issuer)" \
  bash -c '! gp_ssl_is_letsencrypt_file "'"${TMP}/deploy/fullchain.pem"'"'

# Fake live tree
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "${TMP}/live/gsp.g1-host.ch/privkey.pem" \
  -out "${TMP}/live/gsp.g1-host.ch/fullchain.pem" \
  -days 1 -subj "/CN=gsp.g1-host.ch/O=FakeLE" >/dev/null 2>&1

gp_ssl_live_dir() { echo "${TMP}/live/${1}"; }
gp_ssl_has_live() { [[ -f "${TMP}/live/${1}/fullchain.pem" ]]; }

assert "live exists" gp_ssl_has_live "gsp.g1-host.ch"

gp_ssl_install_from_live "${TMP}/deploy" "gsp.g1-host.ch"
assert "after copy marker letsencrypt" test -f "${TMP}/deploy/.ssl_mode"
assert "marker content" bash -c "grep -q letsencrypt '${TMP}/deploy/.ssl_mode'"
issuer="$(openssl x509 -in "${TMP}/deploy/fullchain.pem" -noout -issuer)"
assert "issuer contains FakeLE" bash -c "echo '$issuer' | grep -q FakeLE"
assert "no longer GamePanel O" bash -c "! echo '$issuer' | grep -qE 'O[[:space:]]*=[[:space:]]*GamePanel'"

assert "nginx.conf without Strict-Transport-Security" \
  bash -c "! grep -q 'Strict-Transport-Security' '${ROOT}/deploy/nginx/nginx.conf'"
assert "gp_run_step_always exists" \
  bash -c "grep -q 'gp_run_step_always' '${ROOT}/installer/lib/common.sh'"
assert "panel_ssl always runs" \
  bash -c "grep -q 'gp_run_step_always panel_ssl' '${ROOT}/installer/install-panel.sh'"
assert "phpMyAdmin install fn exists" \
  bash -c "grep -q 'gp_node_install_phpmyadmin' '${ROOT}/installer/install-node.sh'"
assert "firewall opens phpMyAdmin HTTPS" \
  bash -c "grep -q 'phpmyadmin-https\|PHPMYADMIN_HTTPS' '${ROOT}/installer/lib/firewall.sh'"
assert "phpMyAdmin SSL certs fn" \
  bash -c "grep -q 'gp_node_pma_ensure_certs' '${ROOT}/installer/install-node.sh'"
assert "phpMyAdmin ForceSSL / https listen" \
  bash -c "grep -q 'listen.*ssl' '${ROOT}/installer/install-node.sh'"
assert "agent creates DB" \
  bash -c "grep -q 'CREATE DATABASE' '${ROOT}/agent/internal/database/manager.go'"
assert "claim sends phpmyadmin_url" \
  bash -c "grep -q 'phpmyadmin_url' '${ROOT}/installer/install-node.sh'"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
