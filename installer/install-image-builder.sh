#!/usr/bin/env bash
# GamePanel — Image-Builder + Build-Deps auf dem Image-Server
# Läuft allein oder aus install-image-server.sh
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/os.sh"
# shellcheck disable=SC1091
source "${INSTALLER_DIR}/lib/golang.sh"

: "${GAMEPANEL_SOURCE_DIR:=$(cd "${INSTALLER_DIR}/.." && pwd)}"

gp_image_builder_enable_i386() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  if [[ "$arch" == "amd64" ]] && ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
    dpkg --add-architecture i386
    apt-get update -qq
  fi
}

gp_image_builder_install_deps() {
  gp_os_load
  gp_image_builder_enable_i386
  gp_apt_install \
    curl wget ca-certificates git tar gzip zstd unzip zip \
    lib32gcc-s1 lib32stdc++6 || true
  gp_apt_install libcurl4:i386 libcurl4t64:i386 || true
  gp_apt_install python3 jq openssl
}

gp_image_builder_install_steamcmd() {
  local steam_dir="/opt/gamepanel/steamcmd"
  local user="root"
  install -d -m 0755 "$steam_dir"

  if [[ ! -x "${steam_dir}/steamcmd.sh" ]]; then
    gp_info "Installiere SteamCMD für Image-Builds…"
    local tmp="/tmp/steamcmd_linux.tar.gz"
    local url="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    gp_curl_download "$url" "$tmp" || gp_die "SteamCMD Download fehlgeschlagen"
    tar -xzf "$tmp" -C "$steam_dir"
    rm -f "$tmp"
  fi

  # einmalig initialisieren
  if ! "${steam_dir}/steamcmd.sh" +quit; then
    gp_warn "SteamCMD Erststart — Retry…"
    "${steam_dir}/steamcmd.sh" +quit || gp_die "SteamCMD Init fehlgeschlagen"
  fi
  [[ -x "${steam_dir}/steamcmd.sh" ]] || gp_die "steamcmd.sh fehlt"
  ln -sfn "${steam_dir}/steamcmd.sh" /usr/local/bin/steamcmd
  gp_ok "SteamCMD: ${steam_dir}/steamcmd.sh"
}

gp_image_builder_build_cli() {
  local src="${GAMEPANEL_SOURCE_DIR}/image-builder"
  local bin="/usr/local/bin/gamepanel-image"
  local prebuilt="${src}/bin/gamepanel-image"

  [[ -d "$src" ]] || gp_die "image-builder Quelle fehlt: $src"

  if [[ -x "$bin" && "${GAMEPANEL_IMAGE_BUILDER_REINSTALL:-no}" != "yes" ]]; then
    gp_info "gamepanel-image bereits vorhanden: $bin ($("$bin" --help 2>&1 | head -1 || true))"
    # trotzdem prebuild aktualisieren wenn Source neuer
  fi

  if [[ -f "$prebuilt" && "${GAMEPANEL_IMAGE_BUILDER_FORCE_BUILD:-no}" != "yes" ]]; then
    install -m 0755 "$prebuilt" "$bin"
    gp_ok "Prebuilt Image-Builder: $bin"
    return 0
  fi

  gp_install_go
  gp_info "Baue gamepanel-image…"
  install -d -m 0755 "${src}/bin"
  (cd "$src" && CGO_ENABLED=0 go build -ldflags='-s -w' -o bin/gamepanel-image ./cmd/gamepanel-image)
  install -m 0755 "${src}/bin/gamepanel-image" "$bin"
  gp_ok "Image-Builder installiert: $bin"
}

gp_image_builder_write_env() {
  local root="${IMAGE_SERVER_ROOT:-/srv/gamepanel-images}"
  local templates="${GAMEPANEL_SOURCE_DIR}/templates/games"
  cat > /etc/gamepanel/image-builder.env <<EOF
# GamePanel Image Builder
export GAMEPANEL_IMAGE_ROOT=${root}
export GAMEPANEL_TEMPLATES_DIR=${templates}
export STEAMCMD_PATH=/opt/gamepanel/steamcmd/steamcmd.sh
export PATH="/usr/local/go/bin:/usr/local/bin:\${PATH}"
EOF
  chmod 0644 /etc/gamepanel/image-builder.env

  # Convenience wrapper
  cat > /usr/local/bin/gp-image <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
[[ -f /etc/gamepanel/image-builder.env ]] && source /etc/gamepanel/image-builder.env
exec /usr/local/bin/gamepanel-image "$@"
WRAP
  chmod 0755 /usr/local/bin/gp-image
  gp_ok "Env: /etc/gamepanel/image-builder.env — Wrapper: gp-image"
}

gp_install_image_builder() {
  gp_log_info "Image-Builder Installation"
  gp_os_require_supported
  gp_run_step imgb_deps "Build-Deps (zstd, lib32, …)" gp_image_builder_install_deps
  gp_run_step imgb_steam "SteamCMD" gp_image_builder_install_steamcmd
  gp_run_step imgb_cli "gamepanel-image Binary" gp_image_builder_build_cli
  gp_run_step imgb_env "Env + Wrapper" gp_image_builder_write_env
  gp_msg ""
  gp_msg "  Fertig. Images bauen:"
  gp_msg "    source /etc/gamepanel/image-builder.env"
  gp_msg "    gp-image list"
  gp_msg "    gp-image build cs2 --version 1.0.0"
  gp_msg "    gp-image verify cs2 --version 1.0.0"
  gp_msg ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gp_require_root
  gp_log_capture
  gp_ensure_dirs
  gp_load_config "${GAMEPANEL_ETC}/installer.env" 2>/dev/null || true
  : "${GAMEPANEL_SOURCE_DIR:=$(cd "${INSTALLER_DIR}/.." && pwd)}"
  export GAMEPANEL_SOURCE_DIR
  gp_install_image_builder
fi
