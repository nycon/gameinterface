#!/usr/bin/env bash
# GamePanel Installer — SSL / TLS Zertifikate für Nginx
set -euo pipefail

# Standard-Pfad im Repo / Panel-Deploy
gp_ssl_default_dir() {
  if [[ -n "${GAMEPANEL_SSL_DIR:-}" ]]; then
    echo "${GAMEPANEL_SSL_DIR}"
    return 0
  fi
  if [[ -n "${GAMEPANEL_PANEL_DIR:-}" && -d "${GAMEPANEL_PANEL_DIR}/deploy/nginx" ]]; then
    echo "${GAMEPANEL_PANEL_DIR}/deploy/nginx/certs"
    return 0
  fi
  if [[ -n "${INSTALLER_DIR:-}" ]]; then
    echo "$(cd "${INSTALLER_DIR}/.." && pwd)/deploy/nginx/certs"
    return 0
  fi
  echo "/etc/gamepanel/certs"
}

gp_ssl_domain() {
  local d
  d="$(gp_get_env PANEL_DOMAIN "")"
  [[ -n "$d" ]] || d="$(gp_get_env SSL_DOMAIN "")"
  [[ -n "$d" ]] || d="localhost"
  echo "$d"
}

gp_ssl_mode() {
  # selfsigned (default) | letsencrypt
  echo "$(gp_get_env SSL_MODE selfsigned)"
}

gp_ssl_ensure_openssl() {
  if ! gp_command_exists openssl; then
    if gp_command_exists apt-get && [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      gp_apt_install openssl
    else
      gp_die "openssl fehlt — bitte installieren (für SSL-Zertifikate)."
    fi
  fi
}

# Erzeugt self-signed Zertifikat (SAN: Domain, localhost, 127.0.0.1)
gp_ssl_generate_selfsigned() {
  local dir="$1"
  local domain="$2"
  local days="${3:-825}"
  local key="${dir}/privkey.pem"
  local crt="${dir}/fullchain.pem"
  local conf

  install -d -m 0755 "$dir"
  gp_ssl_ensure_openssl

  if [[ -f "$key" && -f "$crt" && "${SSL_FORCE_REGEN:-no}" != "yes" ]]; then
    gp_info "SSL-Zertifikat existiert bereits: ${crt} (SSL_FORCE_REGEN=yes zum Neu erzeugen)"
    return 0
  fi

  conf="$(mktemp)"
  cat > "$conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = ${domain}
O = GamePanel
OU = Installer

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${domain}
DNS.2 = localhost
DNS.3 = *.${domain}
IP.1 = 127.0.0.1
EOF

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key" \
    -out "$crt" \
    -days "$days" \
    -config "$conf" \
    >/dev/null 2>&1
  rm -f "$conf"

  chmod 0640 "$key"
  chmod 0644 "$crt"
  # Metadaten
  cat > "${dir}/README.txt" <<EOF
GamePanel SSL certificates
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Mode: self-signed
Domain/CN: ${domain}
Files: fullchain.pem, privkey.pem

Browsers zeigen bei self-signed eine Warnung — das ist normal im Lab.
Production: SSL_MODE=letsencrypt und Domain auf den Panel-Server zeigen.
EOF

  gp_ok "Self-Signed Zertifikat erzeugt für ${domain} → ${dir}"
}

# Let's Encrypt via certbot (nur root / Linux Panel)
gp_ssl_generate_letsencrypt() {
  local dir="$1"
  local domain="$2"
  local email="$3"
  local live="/etc/letsencrypt/live/${domain}"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    gp_warn "Let's Encrypt braucht root — fallback auf self-signed"
    gp_ssl_generate_selfsigned "$dir" "$domain"
    return 0
  fi

  if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
    gp_warn "Let's Encrypt nicht für localhost — self-signed"
    gp_ssl_generate_selfsigned "$dir" "$domain"
    return 0
  fi

  gp_apt_install certbot
  install -d -m 0755 "$dir"

  # Standalone: Port 80 muss frei sein (Panel ggf. noch nicht gestartet)
  if certbot certonly --standalone --non-interactive --agree-tos \
      --email "$email" \
      -d "$domain" \
      --preferred-challenges http \
      ${SSL_FORCE_REGEN:+--force-renewal}; then
    install -m 0644 "${live}/fullchain.pem" "${dir}/fullchain.pem"
    install -m 0640 "${live}/privkey.pem" "${dir}/privkey.pem"
    cat > "${dir}/README.txt" <<EOF
GamePanel SSL certificates
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Mode: letsencrypt
Domain: ${domain}
Source: ${live}
EOF
    gp_ok "Let's Encrypt Zertifikat für ${domain} eingebunden → ${dir}"
  else
    gp_warn "Let's Encrypt fehlgeschlagen — fallback self-signed"
    gp_ssl_generate_selfsigned "$dir" "$domain"
  fi
}

# Haupt-Entry: Zertifikate sicherstellen
gp_ssl_ensure() {
  local dir domain mode email
  dir="$(gp_ssl_default_dir)"
  domain="$(gp_ssl_domain)"
  mode="$(gp_ssl_mode)"
  email="$(gp_get_env SSL_EMAIL "")"
  [[ -n "$email" ]] || email="$(gp_get_env ACME_EMAIL "")"
  [[ -n "$email" ]] || email="$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@gamepanel.local)"

  gp_info "SSL sicherstellen (mode=${mode}, domain=${domain}, dir=${dir})"

  case "$mode" in
    letsencrypt|acme|le)
      gp_ssl_generate_letsencrypt "$dir" "$domain" "$email"
      ;;
    selfsigned|self|*)
      gp_ssl_generate_selfsigned "$dir" "$domain"
      ;;
  esac

  [[ -f "${dir}/fullchain.pem" && -f "${dir}/privkey.pem" ]] \
    || gp_die "SSL-Zertifikate fehlen unter ${dir}"

  # Für Docker Compose / Installer-Env merken
  gp_merge_env_key SSL_CERT_DIR "$dir" 2>/dev/null || true
  gp_merge_env_key PANEL_DOMAIN "$domain" 2>/dev/null || true
  export GAMEPANEL_SSL_DIR="$dir"
}
