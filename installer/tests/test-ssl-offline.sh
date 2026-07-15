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

# Fake "live" LE tree + deploy with self-signed
mkdir -p "${TMP}/live/gsp.g1-host.ch" "${TMP}/deploy"
# Simulate LE cert (self-signed with different O so is_selfsigned GamePanel check differs —
# we test copy/overwrite mechanics and identity helpers with generated certs)

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "${TMP}/live/gsp.g1-host.ch/privkey.pem" \
  -out "${TMP}/live/gsp.g1-host.ch/fullchain.pem" \
  -days 1 -subj "/CN=gsp.g1-host.ch/O=FakeLE" >/dev/null 2>&1

# Create GamePanel self-signed in deploy
GAMEPANEL_SSL_DIR="${TMP}/deploy"
SSL_FORCE_REGEN=yes gp_ssl_generate_selfsigned "${TMP}/deploy" "gsp.g1-host.ch"
assert "deploy starts self-signed" gp_ssl_is_selfsigned_file "${TMP}/deploy/fullchain.pem"

# Override live path helpers for test by copying via install_from_live with mocked live_dir
# We call install with overridden function
gp_ssl_live_dir() { echo "${TMP}/live/${1}"; }
gp_ssl_has_live() { [[ -f "${TMP}/live/${1}/fullchain.pem" ]]; }

assert "live exists" gp_ssl_has_live "gsp.g1-host.ch"

gp_ssl_install_from_live "${TMP}/deploy" "gsp.g1-host.ch"
assert "after copy marker letsencrypt" test -f "${TMP}/deploy/.ssl_mode"
assert "marker content" bash -c "grep -q letsencrypt '${TMP}/deploy/.ssl_mode'"
issuer="$(openssl x509 -in "${TMP}/deploy/fullchain.pem" -noout -issuer)"
assert "issuer contains FakeLE" bash -c "echo '$issuer' | grep -q FakeLE"
assert "no longer GamePanel O" bash -c "! echo '$issuer' | grep -q 'O = GamePanel'"

# nginx.conf must not force HSTS (locks Firefox with self-signed)
assert "nginx.conf without Strict-Transport-Security" \
  bash -c "! grep -q 'Strict-Transport-Security' '${ROOT}/deploy/nginx/nginx.conf'"

# phpMyAdmin installer functions exist
assert "phpMyAdmin install fn exists" \
  bash -c "grep -q 'gp_node_install_phpmyadmin' '${ROOT}/installer/install-node.sh'"
assert "firewall opens 8081" \
  bash -c "grep -q 'PHPMYADMIN_PORT' '${ROOT}/installer/lib/firewall.sh'"
assert "agent creates DB" \
  bash -c "grep -q 'CREATE DATABASE' '${ROOT}/agent/internal/database/manager.go'"
assert "claim sends phpmyadmin_url" \
  bash -c "grep -q 'phpmyadmin_url' '${ROOT}/installer/install-node.sh'"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
