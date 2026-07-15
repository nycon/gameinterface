#!/usr/bin/env bash
# minecraft-update.sh – Minecraft Server JAR herunterladen/aktualisieren
set -euo pipefail

: "${SERVER_DIR:=/server}"
: "${SERVER_JAR:=server.jar}"
: "${MINECRAFT_VERSION:=latest}"

MANIFEST_URL="https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"

log() {
  echo "[minecraft-update] $*"
}

mkdir -p "${SERVER_DIR}"
cd "${SERVER_DIR}"

resolve_version_url() {
  local version="$1"
  if [[ "${version}" == "latest" ]]; then
    curl -fsSL "${MANIFEST_URL}" \
      | jq -r '.latest.release as $v | .versions[] | select(.id == $v) | .url'
  else
    curl -fsSL "${MANIFEST_URL}" \
      | jq -r --arg v "${version}" '.versions[] | select(.id == $v) | .url'
  fi
}

log "Lade Version ${MINECRAFT_VERSION}"

version_url="$(resolve_version_url "${MINECRAFT_VERSION}")"
if [[ -z "${version_url}" || "${version_url}" == "null" ]]; then
  echo "Version nicht gefunden: ${MINECRAFT_VERSION}" >&2
  exit 1
fi

server_url="$(curl -fsSL "${version_url}" | jq -r '.downloads.server.url')"
if [[ -z "${server_url}" || "${server_url}" == "null" ]]; then
  echo "Kein Server-Download für Version ${MINECRAFT_VERSION}" >&2
  exit 1
fi

curl -fsSL "${server_url}" -o "${SERVER_JAR}.tmp"
mv "${SERVER_JAR}.tmp" "${SERVER_JAR}"

if [[ ! -f eula.txt ]]; then
  echo "eula=true" > eula.txt
fi

log "Server JAR aktualisiert: ${SERVER_JAR}"
