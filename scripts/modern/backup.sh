#!/usr/bin/env bash
# backup.sh – Server-Backup für GamePanel (World + Config)
set -euo pipefail

: "${SERVER_DIR:=/server}"
: "${BACKUP_DIR:=/backups}"
: "${BACKUP_NAME:=$(basename "${SERVER_DIR}")}"
: "${BACKUP_RETENTION:=5}"
: "${BACKUP_PATHS:=world server.properties config}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="${BACKUP_DIR}/${BACKUP_NAME}-${timestamp}.tar.zst"

log() {
  echo "[backup] $*"
}

mkdir -p "${BACKUP_DIR}"
cd "${SERVER_DIR}"

paths=()
for item in ${BACKUP_PATHS}; do
  if [[ -e "${item}" ]]; then
    paths+=("${item}")
  fi
done

if [[ ${#paths[@]} -eq 0 ]]; then
  log "Keine Backup-Pfade gefunden in ${SERVER_DIR}"
  exit 1
fi

log "Erstelle Backup: ${archive}"
tar -cf - "${paths[@]}" | zstd -T0 -o "${archive}"

log "Backup fertig ($(du -h "${archive}" | cut -f1))"

if [[ "${BACKUP_RETENTION}" =~ ^[0-9]+$ ]] && [[ "${BACKUP_RETENTION}" -gt 0 ]]; then
  ls -1t "${BACKUP_DIR}/${BACKUP_NAME}-"*.tar.zst 2>/dev/null \
    | tail -n +"$((BACKUP_RETENTION + 1))" \
    | xargs -r rm -f
  log "Retention: max ${BACKUP_RETENTION} Backups"
fi
