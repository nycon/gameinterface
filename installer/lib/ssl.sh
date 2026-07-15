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

gp_ssl_live_dir() {
  local domain="$1"
  echo "/etc/letsencrypt/live/${domain}"
}

gp_ssl_has_live() {
  local live
  live="$(gp_ssl_live_dir "$1")"
  [[ -f "${live}/fullchain.pem" && -f "${live}/privkey.pem" ]]
}

# Kopiert Let's-Encrypt Live-Certs nach deploy/nginx/certs (immer überschreiben)
gp_ssl_install_from_live() {
  local dir="$1"
  local domain="$2"
  local live
  live="$(gp_ssl_live_dir "$domain")"

  [[ -f "${live}/fullchain.pem" && -f "${live}/privkey.pem" ]] \
    || gp_die "Let's Encrypt Live-Cert fehlt: ${live}"

  install -d -m 0755 "$dir"
  # follow symlink from /etc/letsencrypt/live → archive
  install -m 0644 "$(readlink -f "${live}/fullchain.pem" 2>/dev/null || echo "${live}/fullchain.pem")" \
    "${dir}/fullchain.pem"
  install -m 0640 "$(readlink -f "${live}/privkey.pem" 2>/dev/null || echo "${live}/privkey.pem")" \
    "${dir}/privkey.pem"

  # Marker: echtes LE (nicht Self-Signed)
  echo "letsencrypt" > "${dir}/.ssl_mode"
  cat > "${dir}/README.txt" <<EOF
GamePanel SSL certificates
Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Mode: letsencrypt
Domain: ${domain}
Source: ${live}
Issuer: $(openssl x509 -in "${dir}/fullchain.pem" -noout -issuer 2>/dev/null || echo unknown)
NotAfter: $(openssl x509 -in "${dir}/fullchain.pem" -noout -enddate 2>/dev/null || echo unknown)
EOF

  gp_ok "Let's Encrypt Zertifikat eingebunden → ${dir}"
  gp_ssl_print_identity "$dir"
}

gp_ssl_print_identity() {
  local dir="$1"
  local issuer subject
  issuer="$(openssl x509 -in "${dir}/fullchain.pem" -noout -issuer 2>/dev/null || true)"
  subject="$(openssl x509 -in "${dir}/fullchain.pem" -noout -subject 2>/dev/null || true)"
  gp_info "Cert subject: ${subject}"
  gp_info "Cert issuer:  ${issuer}"
  if [[ "$issuer" == "$subject" ]] || echo "$issuer" | grep -qi 'GamePanel\|O = GamePanel'; then
    gp_warn "Aktives Zertifikat ist SELF-SIGNED — Browser warnen / HSTS blockiert Ausnahmen"
  fi
}

gp_ssl_is_selfsigned_file() {
  local crt="$1"
  [[ -f "$crt" ]] || return 1
  local issuer subject
  issuer="$(openssl x509 -in "$crt" -noout -issuer 2>/dev/null || true)"
  subject="$(openssl x509 -in "$crt" -noout -subject 2>/dev/null || true)"
  [[ -n "$issuer" && "$issuer" == "$subject" ]]
}

# Stoppt den Panel-Proxy kurz, damit certbot --standalone Port 80 nutzen kann
gp_ssl_release_port80() {
  local dir="${GAMEPANEL_PANEL_DIR:-}"
  [[ -n "$dir" && -f "${dir}/docker-compose.yml" ]] || return 0

  # shellcheck disable=SC1091
  [[ -n "${INSTALLER_DIR:-}" ]] && source "${INSTALLER_DIR}/lib/docker.sh" 2>/dev/null || true
  if declare -F gp_docker_compose >/dev/null 2>&1; then
    gp_info "Stoppe Panel-Proxy für ACME (Port 80)…"
    local cf=()
    while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir" 2>/dev/null || printf '%s\n' -f "${dir}/docker-compose.yml")
    (cd "$dir" && gp_docker_compose "${cf[@]}" stop proxy) 2>/dev/null || true
  fi

  # Falls noch Host-Nginx
  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl stop nginx 2>/dev/null || true
  fi
  sleep 1
}

gp_ssl_restore_proxy() {
  local dir="${GAMEPANEL_PANEL_DIR:-}"
  [[ -n "$dir" && -f "${dir}/docker-compose.yml" ]] || return 0
  # shellcheck disable=SC1091
  [[ -n "${INSTALLER_DIR:-}" ]] && source "${INSTALLER_DIR}/lib/docker.sh" 2>/dev/null || true
  if declare -F gp_docker_compose >/dev/null 2>&1; then
    gp_info "Starte Panel-Proxy neu…"
    local cf=()
    while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir" 2>/dev/null || printf '%s\n' -f "${dir}/docker-compose.yml")
    (cd "$dir" && gp_docker_compose "${cf[@]}" up -d proxy) 2>/dev/null || true
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
    if gp_ssl_is_selfsigned_file "$crt"; then
      gp_info "Self-Signed Zertifikat existiert bereits: ${crt} (SSL_FORCE_REGEN=yes zum Neu erzeugen)"
      return 0
    fi
    # echtes LE nicht mit Self-Signed überschreiben
    gp_info "Vorhandenes Zertifikat behalten (kein Self-Signed Override): ${crt}"
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
  echo "selfsigned" > "${dir}/.ssl_mode"
  cat > "${dir}/README.txt" <<EOF
GamePanel SSL certificates
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Mode: self-signed
Domain/CN: ${domain}
Files: fullchain.pem, privkey.pem

Browsers zeigen bei self-signed eine Warnung.
Production: SSL_MODE=letsencrypt und Domain auf den Panel-Server zeigen.
EOF

  gp_ok "Self-Signed Zertifikat erzeugt für ${domain} → ${dir}"
}

gp_ssl_setup_renew_hook() {
  local domain="$1"
  local dir="$2"
  local panel_root hook
  panel_root="$(cd "${dir}/../.." && pwd)"
  hook="/etc/letsencrypt/renewal-hooks/deploy/gamepanel-copy-certs.sh"
  install -d -m 0755 "$(dirname "$hook")"
  cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${domain}"
DEST="${dir}"
PANEL_DIR="${panel_root}"
LIVE="/etc/letsencrypt/live/\${DOMAIN}"
if [[ -f "\${LIVE}/fullchain.pem" && -f "\${LIVE}/privkey.pem" ]]; then
  install -m 0644 "\$(readlink -f "\${LIVE}/fullchain.pem")" "\${DEST}/fullchain.pem"
  install -m 0640 "\$(readlink -f "\${LIVE}/privkey.pem")" "\${DEST}/privkey.pem"
  echo letsencrypt > "\${DEST}/.ssl_mode"
fi
if [[ -f "\${PANEL_DIR}/docker-compose.yml" ]]; then
  (cd "\${PANEL_DIR}" && docker compose exec -T proxy nginx -s reload) 2>/dev/null \\
    || (cd "\${PANEL_DIR}" && docker compose restart proxy) 2>/dev/null \\
    || true
fi
EOF
  chmod 0755 "$hook"
  gp_ok "certbot Renew-Hook: ${hook}"
}

# Let's Encrypt via certbot (nur root / Linux Panel)
gp_ssl_generate_letsencrypt() {
  local dir="$1"
  local domain="$2"
  local email="$3"
  local allow_fallback="${SSL_ALLOW_SELF_SIGNED_FALLBACK:-no}"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    gp_die "Let's Encrypt braucht root. Ohne Root: --ssl-mode selfsigned"
  fi

  if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" || "$domain" == *.local ]]; then
    gp_die "Let's Encrypt nicht für Domain '${domain}' — echte öffentliche Domain nötig"
  fi

  [[ -n "$email" && "$email" == *@* ]] || gp_die "Gültige E-Mail für Let's Encrypt nötig (SSL_EMAIL / --admin-email)"

  install -d -m 0755 "$dir"
  gp_apt_install certbot openssl

  # Bereits vorhanden unter /etc/letsencrypt → immer nach deploy kopieren
  if gp_ssl_has_live "$domain"; then
    gp_info "Bestehendes Let's Encrypt Zertifikat gefunden — kopiere nach ${dir}"
    gp_ssl_install_from_live "$dir" "$domain"
    gp_ssl_setup_renew_hook "$domain" "$dir"
    return 0
  fi

  # Port 80 freigeben (Docker-Proxy blockiert sonst certbot standalone)
  gp_ssl_release_port80

  local certbot_ok=0
  local extra=()
  if [[ "${SSL_FORCE_REGEN:-no}" == "yes" ]]; then
    extra+=(--force-renewal)
  fi

  gp_info "certbot standalone für ${domain} (E-Mail ${email})…"
  if certbot certonly --standalone --non-interactive --agree-tos \
      --email "$email" \
      -d "$domain" \
      --preferred-challenges http \
      "${extra[@]+"${extra[@]}"}"; then
    certbot_ok=1
  fi

  if [[ "$certbot_ok" -ne 1 ]] && gp_ssl_has_live "$domain"; then
    # z.B. Rate-Limit aber Cert existiert doch
    certbot_ok=1
  fi

  if [[ "$certbot_ok" -eq 1 ]] && gp_ssl_has_live "$domain"; then
    gp_ssl_install_from_live "$dir" "$domain"
    gp_ssl_setup_renew_hook "$domain" "$dir"
    gp_ssl_restore_proxy
    return 0
  fi

  gp_ssl_restore_proxy

  gp_err "Let's Encrypt fehlgeschlagen für ${domain}."
  gp_msg "Prüfen:"
  gp_msg "  1) DNS A-Record ${domain} zeigt auf diese Server-IP"
  gp_msg "  2) Port 80 von außen erreichbar (Firewall/Cloud)"
  gp_msg "  3) Log: journalctl -u certbot /var/log/letsencrypt/letsencrypt.log"
  if [[ "$allow_fallback" == "yes" ]]; then
    gp_warn "SSL_ALLOW_SELF_SIGNED_FALLBACK=yes — erzeuge Self-Signed (Browser-Warnung!)"
    SSL_FORCE_REGEN=yes gp_ssl_generate_selfsigned "$dir" "$domain"
    return 0
  fi
  gp_die "Abbruch: kein gültiges Let's Encrypt Zertifikat. Erneut: sudo ./install.sh --role panel --fix-ssl --domain ${domain} --ssl-mode letsencrypt --admin-email ${email}"
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
      # Wenn deploy noch Self-Signed hat aber Live-LE existiert → reparieren
      if gp_ssl_has_live "$domain"; then
        gp_ssl_install_from_live "$dir" "$domain"
        gp_ssl_setup_renew_hook "$domain" "$dir"
      else
        gp_ssl_generate_letsencrypt "$dir" "$domain" "$email"
      fi
      ;;
    selfsigned|self|*)
      gp_ssl_generate_selfsigned "$dir" "$domain"
      ;;
  esac

  [[ -f "${dir}/fullchain.pem" && -f "${dir}/privkey.pem" ]] \
    || gp_die "SSL-Zertifikate fehlen unter ${dir}"

  gp_ssl_print_identity "$dir"

  # Für Docker Compose / Installer-Env merken
  gp_merge_env_key SSL_CERT_DIR "$dir" 2>/dev/null || true
  gp_merge_env_key PANEL_DOMAIN "$domain" 2>/dev/null || true
  gp_merge_env_key SSL_MODE "$mode" 2>/dev/null || true
  export GAMEPANEL_SSL_DIR="$dir"
}

# Reparatur: Zertifikat neu holen/kopieren + Proxy reload
gp_ssl_fix() {
  export SSL_FORCE_REGEN="${SSL_FORCE_REGEN:-no}"
  local dir domain mode
  dir="$(gp_ssl_default_dir)"
  domain="$(gp_ssl_domain)"
  mode="$(gp_ssl_mode)"

  gp_info "=== SSL Fix (${mode} / ${domain}) ==="

  if [[ "$mode" == "letsencrypt" || "$mode" == "acme" || "$mode" == "le" ]]; then
    # Alten Self-Signed in deploy überschreiben lassen
    if gp_ssl_is_selfsigned_file "${dir}/fullchain.pem"; then
      gp_warn "Self-Signed in ${dir} wird durch Let's Encrypt ersetzt"
      rm -f "${dir}/fullchain.pem" "${dir}/privkey.pem" "${dir}/.ssl_mode"
    fi
    # Live vorhanden → nur kopieren; sonst neu ausstellen
    if gp_ssl_has_live "$domain" && [[ "${SSL_FORCE_REGEN:-no}" != "yes" ]]; then
      gp_ssl_install_from_live "$dir" "$domain"
      gp_ssl_setup_renew_hook "$domain" "$dir"
    else
      export SSL_FORCE_REGEN="${SSL_FORCE_REGEN:-no}"
      gp_ssl_generate_letsencrypt "$dir" "$domain" \
        "$(gp_get_env SSL_EMAIL "$(gp_get_env GAMEPANEL_ADMIN_EMAIL "")")"
    fi
  else
    export SSL_FORCE_REGEN=yes
    gp_ssl_generate_selfsigned "$dir" "$domain"
  fi

  gp_ssl_restore_proxy
  # Extra reload falls Proxy schon lief
  local panel="${GAMEPANEL_PANEL_DIR:-$(cd "${dir}/../.." && pwd)}"
  if [[ -f "${panel}/docker-compose.yml" ]]; then
    (cd "$panel" && docker compose exec -T proxy nginx -s reload) 2>/dev/null \
      || (cd "$panel" && docker compose restart proxy) 2>/dev/null \
      || true
  fi

  gp_ok "SSL Fix fertig. Test: curl -vI https://${domain}/ 2>&1 | grep -i 'subject:\\|issuer:\\|expire'"
  gp_msg "Falls Firefox noch HSTS-Fehler zeigt: about:preferences#privacy → Zertifikate /"
  gp_msg "  oder Einstellungen → Datenschutz → „Cookies und Websitedaten löschen“ für ${domain}"
  gp_msg "  oder einmal: about:networking#security → HSTS für Domain löschen"
}
