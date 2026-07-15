#!/usr/bin/env bash
# GamePanel Installer — SSL / TLS Zertifikate für Nginx
#
# Regel: SSL_MODE=letsencrypt funktioniert beim normalen Panel-Install.
# Existiert bereits /etc/letsencrypt/live/<domain>/ → nur kopieren (kein neues
# Zertifikat, kein Rate-Limit). Self-Signed wird dabei überschrieben.
set -euo pipefail

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
  echo "/etc/letsencrypt/live/${1}"
}

gp_ssl_has_live() {
  local live
  live="$(gp_ssl_live_dir "$1")"
  [[ -f "${live}/fullchain.pem" && -f "${live}/privkey.pem" ]]
}

# Neueste Datei aus archive/<domain>/ (auch wenn live/ gelöscht wurde)
gp_ssl_archive_latest() {
  local domain="$1" kind="$2" # fullchain|privkey|cert|chain
  local arch="/etc/letsencrypt/archive/${domain}"
  local f
  [[ -d "$arch" ]] || return 1
  # shellcheck disable=SC2086,SC2012
  f="$(ls -1 "${arch}/${kind}"*.pem 2>/dev/null | sort -V | tail -1 || true)"
  [[ -n "$f" && -f "$f" ]] || return 1
  echo "$f"
}

gp_ssl_abs() {
  readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || echo "$1"
}

# Stellt live/ aus archive/ wieder her und kopiert nach deploy — OHNE certbot
gp_ssl_recover_from_archive() {
  local dir="$1"
  local domain="$2"
  local fullchain privkey live abs_full abs_key

  fullchain="$(gp_ssl_archive_latest "$domain" fullchain)" || return 1
  privkey="$(gp_ssl_archive_latest "$domain" privkey)" || return 1

  install -d -m 0755 "$dir"
  # Direkt nach deploy (Panel nutzt das) — kein certbot nötig
  install -m 0644 "$fullchain" "${dir}/fullchain.pem"
  install -m 0644 "$privkey" "${dir}/privkey.pem"
  echo "letsencrypt" > "${dir}/.ssl_mode"

  # live/ wiederherstellen damit certbot renew später klappt
  live="$(gp_ssl_live_dir "$domain")"
  install -d -m 0755 "$live"
  abs_full="$(gp_ssl_abs "$fullchain")"
  abs_key="$(gp_ssl_abs "$privkey")"
  ln -sfn "$abs_full" "${live}/fullchain.pem"
  ln -sfn "$abs_key" "${live}/privkey.pem"
  local cert chain
  cert="$(gp_ssl_archive_latest "$domain" cert 2>/dev/null || true)"
  chain="$(gp_ssl_archive_latest "$domain" chain 2>/dev/null || true)"
  [[ -n "${cert:-}" && -f "$cert" ]] && ln -sfn "$(gp_ssl_abs "$cert")" "${live}/cert.pem" || true
  [[ -n "${chain:-}" && -f "$chain" ]] && ln -sfn "$(gp_ssl_abs "$chain")" "${live}/chain.pem" || true

  cat > "${dir}/README.txt" <<EOF
GamePanel SSL certificates
Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Mode: letsencrypt (recovered from archive — no new issuance)
Domain: ${domain}
Source: ${fullchain}
Issuer: $(openssl x509 -in "${dir}/fullchain.pem" -noout -issuer 2>/dev/null || echo unknown)
NotAfter: $(openssl x509 -in "${dir}/fullchain.pem" -noout -enddate 2>/dev/null || echo unknown)
EOF

  gp_ok "Let's Encrypt aus Archive wiederhergestellt → ${dir}"
  gp_ssl_print_identity "$dir"
  gp_ssl_setup_renew_hook "$domain" "$dir"
  return 0
}

# Domain mit Archive-Certs finden (exakte Domain zuerst)
gp_ssl_discover_archive_domain() {
  local want="$1" d f
  f="$(gp_ssl_archive_latest "$want" fullchain 2>/dev/null || true)"
  if [[ -n "$f" ]] && gp_ssl_archive_latest "$want" privkey >/dev/null 2>&1; then
    echo "$want"
    return 0
  fi
  [[ -d /etc/letsencrypt/archive ]] || return 1
  for d in /etc/letsencrypt/archive/*/; do
    [[ -d "$d" ]] || continue
    d="$(basename "$d")"
    f="$(gp_ssl_archive_latest "$d" fullchain 2>/dev/null || true)"
    if [[ -n "$f" ]] && gp_ssl_archive_latest "$d" privkey >/dev/null 2>&1; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# Falls Domain-Mismatch: erstes Live-Zertifikat finden (ohne README)
gp_ssl_discover_live_domain() {
  local want="$1" d
  if gp_ssl_has_live "$want"; then
    echo "$want"
    return 0
  fi
  [[ -d /etc/letsencrypt/live ]] || return 1
  for d in /etc/letsencrypt/live/*/; do
    [[ -d "$d" ]] || continue
    d="$(basename "$d")"
    [[ "$d" == "README" ]] && continue
    if [[ -f "/etc/letsencrypt/live/${d}/fullchain.pem" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

gp_ssl_install_from_live() {
  local dir="$1"
  local domain="$2"
  local live src_full src_key
  live="$(gp_ssl_live_dir "$domain")"

  [[ -f "${live}/fullchain.pem" && -f "${live}/privkey.pem" ]] \
    || gp_die "Let's Encrypt Live-Cert fehlt: ${live}"

  install -d -m 0755 "$dir"
  src_full="$(readlink -f "${live}/fullchain.pem" 2>/dev/null || echo "${live}/fullchain.pem")"
  src_key="$(readlink -f "${live}/privkey.pem" 2>/dev/null || echo "${live}/privkey.pem")"
  install -m 0644 "$src_full" "${dir}/fullchain.pem"
  install -m 0640 "$src_key" "${dir}/privkey.pem"
  # Nginx im Container muss die Key lesen können
  chmod 0644 "${dir}/privkey.pem" 2>/dev/null || true

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
  if gp_ssl_is_selfsigned_file "${dir}/fullchain.pem"; then
    gp_warn "Aktives Zertifikat ist SELF-SIGNED"
  fi
}

gp_ssl_is_selfsigned_file() {
  local crt="$1"
  [[ -f "$crt" ]] || return 1
  local issuer subject
  issuer="$(openssl x509 -in "$crt" -noout -issuer 2>/dev/null || true)"
  subject="$(openssl x509 -in "$crt" -noout -subject 2>/dev/null || true)"
  # Explizit Installer-Self-Signed (OpenSSL schreibt "O = GamePanel" oder "O=GamePanel")
  if echo "$issuer$subject" | grep -qiE 'O\s*=\s*GamePanel|OU\s*=\s*Installer'; then
    return 0
  fi
  # Klassisch: Issuer == Subject und keine öffentliche CA
  if [[ -n "$issuer" && "$issuer" == "$subject" ]]; then
    if echo "$issuer" | grep -qiE "Let's Encrypt|ISRG|DigiCert|GlobalSign|Sectigo|Amazon"; then
      return 1
    fi
    return 0
  fi
  return 1
}

gp_ssl_is_letsencrypt_file() {
  local crt="$1"
  [[ -f "$crt" ]] || return 1
  local issuer
  issuer="$(openssl x509 -in "$crt" -noout -issuer 2>/dev/null || true)"
  # Wichtig: kein R[0-9]* — matched sonst das Wort "issuer" case-insensitive!
  echo "$issuer" | grep -qiE "Let's Encrypt|ISRG Root|Let's Encrypt Authority"
}

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

  if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl stop nginx 2>/dev/null || true
  fi
  sleep 1
}

gp_ssl_reload_proxy() {
  local dir="${GAMEPANEL_PANEL_DIR:-}"
  [[ -n "$dir" && -f "${dir}/docker-compose.yml" ]] || return 0
  # shellcheck disable=SC1091
  [[ -n "${INSTALLER_DIR:-}" ]] && source "${INSTALLER_DIR}/lib/docker.sh" 2>/dev/null || true
  if ! declare -F gp_docker_compose >/dev/null 2>&1; then
    return 0
  fi
  local cf=()
  while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir" 2>/dev/null || printf '%s\n' -f "${dir}/docker-compose.yml")
  (cd "$dir" && gp_docker_compose "${cf[@]}" up -d proxy) 2>/dev/null || true
  (cd "$dir" && gp_docker_compose "${cf[@]}" exec -T proxy nginx -s reload) 2>/dev/null \
    || (cd "$dir" && gp_docker_compose "${cf[@]}" restart proxy) 2>/dev/null \
    || true
}

gp_ssl_restore_proxy() {
  gp_ssl_reload_proxy
}

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
    if ! gp_ssl_is_selfsigned_file "$crt"; then
      gp_info "Vorhandenes Zertifikat behalten (kein Self-Signed Override): ${crt}"
      return 0
    fi
    gp_info "Self-Signed Zertifikat existiert bereits: ${crt}"
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

  chmod 0644 "$key" "$crt"
  echo "selfsigned" > "${dir}/.ssl_mode"
  cat > "${dir}/README.txt" <<EOF
GamePanel SSL certificates
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Mode: self-signed
Domain/CN: ${domain}
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
  install -m 0644 "\$(readlink -f "\${LIVE}/privkey.pem")" "\${DEST}/privkey.pem"
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

# Nur ausführen wenn KEIN Live-Cert existiert. Nie force-renewal default.
gp_ssl_generate_letsencrypt() {
  local dir="$1"
  local domain="$2"
  local email="$3"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    gp_die "Let's Encrypt braucht root."
  fi

  if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" || "$domain" == *.local ]]; then
    gp_die "Let's Encrypt nicht für Domain '${domain}'"
  fi

  [[ -n "$email" && "$email" == *@* ]] || gp_die "Gültige E-Mail für Let's Encrypt nötig (--admin-email)"

  install -d -m 0755 "$dir"
  gp_apt_install certbot openssl

  local live_domain arch_domain
  if live_domain="$(gp_ssl_discover_live_domain "$domain")"; then
    if [[ "$live_domain" != "$domain" ]]; then
      gp_warn "Live-Cert für '${live_domain}' gefunden (gewünscht: ${domain}) — wird eingebunden"
    fi
    gp_ssl_install_from_live "$dir" "$live_domain"
    gp_ssl_setup_renew_hook "$live_domain" "$dir"
    return 0
  fi

  # Archive retten BEVOR certbot (Rate-Limit!) — live/ war oft gelöscht, Certs sind noch da
  if arch_domain="$(gp_ssl_discover_archive_domain "$domain")"; then
    gp_warn "Kein live/-Link, aber Archive für '${arch_domain}' — stelle wieder her (kein neues Zertifikat)"
    if gp_ssl_recover_from_archive "$dir" "$arch_domain"; then
      gp_ssl_reload_proxy
      return 0
    fi
  fi

  gp_ssl_release_port80

  local certbot_ok=0 certbot_log="/tmp/gamepanel-certbot.out"
  local extra=()
  if [[ "${SSL_FORCE_REGEN:-no}" == "yes" ]]; then
    extra+=(--force-renewal)
  fi

  gp_info "certbot standalone für ${domain} (E-Mail ${email})…"
  if certbot certonly --standalone --non-interactive --agree-tos \
      --email "$email" \
      -d "$domain" \
      --preferred-challenges http \
      "${extra[@]+"${extra[@]}"}" >"$certbot_log" 2>&1; then
    certbot_ok=1
  else
    cat "$certbot_log" >&2 || true
  fi

  if [[ "$certbot_ok" -ne 1 ]] && gp_ssl_has_live "$domain"; then
    certbot_ok=1
  fi

  if [[ "$certbot_ok" -eq 1 ]] && gp_ssl_has_live "$domain"; then
    gp_ssl_install_from_live "$dir" "$domain"
    gp_ssl_setup_renew_hook "$domain" "$dir"
    gp_ssl_reload_proxy
    return 0
  fi

  # Nach Rate-Limit / Fehler: nochmal Archive versuchen
  if arch_domain="$(gp_ssl_discover_archive_domain "$domain")"; then
    gp_warn "certbot fehlgeschlagen — stelle Let's Encrypt aus Archive wieder her"
    if gp_ssl_recover_from_archive "$dir" "$arch_domain"; then
      gp_ssl_reload_proxy
      return 0
    fi
  fi

  gp_ssl_reload_proxy

  if grep -qi 'too many certificates\|rate limit\|retry after' "$certbot_log" 2>/dev/null; then
    local retry
    retry="$(grep -oiE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2}[^ ]*' "$certbot_log" 2>/dev/null | head -1 || true)"
    gp_err "Let's Encrypt Rate-Limit erreicht (5 Certs / 168h für ${domain})."
    [[ -n "$retry" ]] && gp_msg "  ${retry}"
    gp_msg "Bestehende Certs suchen:"
    gp_msg "  sudo ls -la /etc/letsencrypt/archive/${domain}/ || true"
    gp_msg "  sudo certbot certificates"
    gp_msg "Kein neues Zertifikat möglich bis zum Retry — Archive restaurieren oder Temporary Self-Signed."
    # Temporär Self-Signed damit Panel erreichbar bleibt (HSTS ist aus)
    gp_warn "Temporäres Self-Signed bis Rate-Limit vorbei (Firefox: einmal Ausnahme erlauben)"
    SSL_FORCE_REGEN=yes gp_ssl_generate_selfsigned "$dir" "$domain"
    echo "selfsigned-ratelimit" > "${dir}/.ssl_mode"
    gp_ssl_reload_proxy
    gp_ok "Panel läuft mit Self-Signed bis LE wieder möglich ist."
    return 0
  fi

  gp_err "Let's Encrypt fehlgeschlagen für ${domain}."
  gp_msg "Prüfen: DNS A-Record, Port 80 öffentlich, /var/log/letsencrypt/letsencrypt.log"
  gp_msg "Archive: ls /etc/letsencrypt/archive/${domain}/"
  gp_die "Abbruch: kein gültiges Let's Encrypt Zertifikat."
}

gp_ssl_require_letsencrypt_deployed() {
  local dir="$1"
  if gp_ssl_is_letsencrypt_file "${dir}/fullchain.pem"; then
    return 0
  fi
  if [[ -f "${dir}/.ssl_mode" ]] && grep -q 'ratelimit' "${dir}/.ssl_mode"; then
    gp_warn "SSL: temporäres Self-Signed wegen Rate-Limit — OK fürs Panel bis LE wieder geht"
    return 0
  fi
  if gp_ssl_is_selfsigned_file "${dir}/fullchain.pem"; then
    gp_die "SSL_MODE=letsencrypt, aber deploy/nginx/certs ist noch SELF-SIGNED. Archive prüfen unter /etc/letsencrypt/archive/ und Panel-Install erneut."
  fi
  gp_warn "Zertifikat-Issuer nicht als Let's Encrypt erkannt — bitte manuell prüfen"
}

# Haupt-Entry: wird bei jedem Panel-Install aufgerufen
gp_ssl_ensure() {
  local dir domain mode email live_domain arch_domain
  dir="$(gp_ssl_default_dir)"
  domain="$(gp_ssl_domain)"
  mode="$(gp_ssl_mode)"
  email="$(gp_get_env SSL_EMAIL "")"
  [[ -n "$email" ]] || email="$(gp_get_env ACME_EMAIL "")"
  [[ -n "$email" ]] || email="$(gp_get_env GAMEPANEL_ADMIN_EMAIL admin@gamepanel.local)"

  gp_info "SSL sicherstellen (mode=${mode}, domain=${domain}, dir=${dir})"

  case "$mode" in
    letsencrypt|acme|le)
      # 1) live/
      if live_domain="$(gp_ssl_discover_live_domain "$domain")"; then
        gp_info "Live-Cert gefunden (${live_domain}) — kopiere nach deploy (kein neu ausstellen)"
        gp_ssl_install_from_live "$dir" "$live_domain"
        gp_ssl_setup_renew_hook "$live_domain" "$dir"
      # 2) archive/ — VOR certbot (Rate-Limit!)
      elif arch_domain="$(gp_ssl_discover_archive_domain "$domain")"; then
        gp_info "Archive-Cert gefunden (${arch_domain}) — stelle wieder her (kein certbot)"
        gp_ssl_recover_from_archive "$dir" "$arch_domain"
      else
        gp_ssl_generate_letsencrypt "$dir" "$domain" "$email"
      fi
      gp_ssl_require_letsencrypt_deployed "$dir"
      ;;
    selfsigned|self|*)
      gp_ssl_generate_selfsigned "$dir" "$domain"
      ;;
  esac

  [[ -f "${dir}/fullchain.pem" && -f "${dir}/privkey.pem" ]] \
    || gp_die "SSL-Zertifikate fehlen unter ${dir}"

  gp_ssl_print_identity "$dir"
  gp_merge_env_key SSL_CERT_DIR "$dir" 2>/dev/null || true
  gp_merge_env_key PANEL_DOMAIN "$domain" 2>/dev/null || true
  gp_merge_env_key SSL_MODE "$mode" 2>/dev/null || true
  export GAMEPANEL_SSL_DIR="$dir"
}

# Nach Docker-Up: Zertifikat nochmals syncen + Proxy neu laden
gp_ssl_apply_running() {
  gp_ssl_ensure
  gp_ssl_reload_proxy
  gp_ok "SSL aktiv unter deploy/nginx/certs (Proxy neu geladen)"
}
