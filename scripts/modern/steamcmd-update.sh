#!/usr/bin/env bash
# steamcmd-update.sh – SteamCMD App-Update für GamePanel Image Builder
set -euo pipefail

: "${STEAMCMD:=/usr/games/steamcmd}"
: "${SERVER_DIR:=/server}"
: "${STEAM_APP_ID:?STEAM_APP_ID muss gesetzt sein}"
: "${VALIDATE:=0}"

log() {
  echo "[steamcmd-update] $*"
}

mkdir -p "${SERVER_DIR}"

validate_arg=""
if [[ "${VALIDATE}" == "1" || "${VALIDATE}" == "true" ]]; then
  validate_arg="validate"
fi

log "Update App ${STEAM_APP_ID} nach ${SERVER_DIR}"

"${STEAMCMD}" \
  +force_install_dir "${SERVER_DIR}" \
  +login anonymous \
  +app_update "${STEAM_APP_ID}" ${validate_arg} \
  +quit

log "Update abgeschlossen"
