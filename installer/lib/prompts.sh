#!/usr/bin/env bash
# GamePanel Installer — interaktive Eingaben
set -euo pipefail

GP_NON_INTERACTIVE="${GP_NON_INTERACTIVE:-0}"

gp_prompt_bool() {
  local var_name="$1" prompt="$2" default="${3:-yes}"
  if [[ "$GP_NON_INTERACTIVE" == "1" ]]; then
    return 0
  fi
  local dflag="" ans
  [[ "$default" == "yes" ]] && dflag="[J/n]" || dflag="[j/N]"
  while true; do
    read -r -p "${prompt} ${dflag}: " ans || ans=""
    ans="${ans:-}"
    if [[ -z "$ans" ]]; then
      if [[ "$default" == "yes" ]]; then eval "$var_name=yes"; return 0; else eval "$var_name=no"; return 0; fi
    fi
    case "${ans,,}" in
      j|ja|y|yes) eval "$var_name=yes"; return 0 ;;
      n|nein|no) eval "$var_name=no"; return 0 ;;
    esac
    gp_warn "Bitte j oder n eingeben."
  done
}

gp_prompt_value() {
  local var_name="$1" prompt="$2" default="${3:-}" secret="${4:-0}"
  if [[ "$GP_NON_INTERACTIVE" == "1" ]]; then
    if [[ -z "${!var_name:-}" && -n "$default" ]]; then
      eval "$var_name=$(printf '%q' "$default")"
    fi
    return 0
  fi
  local ans
  if [[ "$secret" == "1" ]]; then
    read -r -s -p "${prompt}: " ans
    echo
  else
    local hint=""
    [[ -n "$default" ]] && hint=" [${default}]"
    read -r -p "${prompt}${hint}: " ans
  fi
  ans="${ans:-$default}"
  if [[ -z "$ans" ]]; then
    gp_warn "Leer — Abbruch oder Default nutzen."
    [[ -n "$default" ]] || return 1
  fi
  printf -v "$var_name" '%s' "$ans"
}

gp_prompt_role() {
  local var_name="$1"
  if [[ "$GP_NON_INTERACTIVE" == "1" ]]; then
    return 0
  fi
  gp_msg ""
  gp_msg "${COLOR_BOLD}Installationstyp wählen:${COLOR_RESET}"
  gp_msg "  1) standalone   — Panel + DB + Redis + Image Server (+ optional Node)"
  gp_msg "  2) panel        — Nur Panel-Server (Docker)"
  gp_msg "  3) image-server — Image/SFTP Server"
  gp_msg "  4) node         — Game Node"
  gp_msg "  5) database     — Dedizierter DB-Server"
  gp_msg "  6) worker       — Queue Worker"
  local choice
  read -r -p "Auswahl [1-6]: " choice
  case "$choice" in
    1) eval "$var_name=standalone" ;;
    2) eval "$var_name=panel" ;;
    3) eval "$var_name=image-server" ;;
    4) eval "$var_name=node" ;;
    5) eval "$var_name=database" ;;
    6) eval "$var_name=worker" ;;
    *) gp_die "Ungültige Auswahl" ;;
  esac
}

gp_confirm() {
  local prompt="$1"
  [[ "$GP_NON_INTERACTIVE" == "1" ]] && return 0
  local ans
  read -r -p "${prompt} [j/N]: " ans
  [[ "${ans,,}" == "j" || "${ans,,}" == "ja" || "${ans,,}" == "y" ]]
}
