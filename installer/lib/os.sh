#!/usr/bin/env bash
# GamePanel Installer — Betriebssystem-Erkennung
set -euo pipefail

GP_OS_ID=""
GP_OS_VERSION_ID=""
GP_OS_CODENAME=""
GP_OS_PRETTY=""
GP_OS_FAMILY="debian"

gp_os_load() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    GP_OS_ID="${ID:-}"
    GP_OS_VERSION_ID="${VERSION_ID:-}"
    GP_OS_CODENAME="${VERSION_CODENAME:-}"
    GP_OS_PRETTY="${PRETTY_NAME:-}"
  else
    gp_die "Keine /etc/os-release gefunden — unsupported OS."
  fi

  case "${GP_OS_ID}" in
    debian|ubuntu) GP_OS_FAMILY="debian" ;;
    *) gp_die "Nicht unterstütztes OS: ${GP_OS_ID} (${GP_OS_PRETTY})" ;;
  esac
}

gp_os_supported() {
  gp_os_load
  case "${GP_OS_ID}:${GP_OS_VERSION_ID}" in
    debian:12*) return 0 ;;
    debian:13*) gp_warn "Debian 13 (Trixie) — Vorbereitung, noch nicht voll zertifiziert."; return 0 ;;
    ubuntu:24.04*) return 0 ;;
    *) return 1 ;;
  esac
}

gp_os_require_supported() {
  gp_os_load
  if ! gp_os_supported; then
    gp_die "Nur Debian 12, Debian 13 (prep) und Ubuntu 24.04 LTS werden unterstützt. Erkannt: ${GP_OS_PRETTY}"
  fi
  gp_log_info "OS: ${GP_OS_PRETTY} (Arch: $(gp_detect_arch))"
}

gp_os_pkg_manager() {
  if gp_command_exists apt-get; then
    echo apt
  else
    gp_die "Kein apt-basiertes System."
  fi
}

gp_os_kernel_version() {
  uname -r
}

gp_os_is_cgroup_v2() {
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    return 0
  fi
  if mount | grep -q 'type cgroup2'; then
    return 0
  fi
  return 1
}

gp_os_check_cgroup_v2() {
  if gp_os_is_cgroup_v2; then
    gp_ok "cgroups v2 aktiv"
    return 0
  fi
  gp_warn "cgroups v2 nicht erkannt — Game Nodes benötigen cgroups v2."
  return 1
}

gp_os_check_kernel_modules() {
  local mods=(nf_conntrack iptable_nat ip_tables)
  local m
  for m in "${mods[@]}"; do
    if ! lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$m"; then
      if [[ -d "/lib/modules/$(uname -r)" ]]; then
        modprobe "$m" 2>/dev/null || gp_warn "Kernel-Modul $m nicht geladen (optional)."
      fi
    fi
  done
}
