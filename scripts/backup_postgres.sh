#!/usr/bin/env bash
set -euo pipefail

# File4Base PostgreSQL Backup & Restore Script
#
# Works against the running `file4base-postgres` container, whose data lives in
# the named Docker volume `file4base-postgres-data`.
#
#   ./scripts/backup_postgres.sh backup            # all databases + roles
#   ./scripts/backup_postgres.sh restore <file>    # restore a backup file
#   ./scripts/backup_postgres.sh list              # list existing backups
#
# Backups are written to ./backups (ignored by git), or to BACKUP_DIR if set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
CONTAINER="file4base-postgres"
DB_USER="file4base"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"

usage() {
    echo "Usage: $0 [backup|restore <file>|list]"
    exit 1
}

require_container() {
    if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null)" != "true" ]; then
        echo "Container ${CONTAINER} is not running. Start it with: docker compose up -d postgres"
        exit 1
    fi
}

backup() {
    require_container
    mkdir -p "${BACKUP_DIR}"
    local file="${BACKUP_DIR}/file4base-postgres-v${VERSION}-$(date +%Y%m%d-%H%M%S).sql.gz"

    echo "Backing up all databases from ${CONTAINER} ..."
    docker exec "${CONTAINER}" pg_dumpall -U "${DB_USER}" --clean --if-exists | gzip > "${file}"

    echo "Backup written to: ${file} ($(du -h "${file}" | cut -f1))"
}

restore() {
    local file="${1:-}"
    [ -n "${file}" ] || usage
    [ -f "${file}" ] || { echo "Backup file not found: ${file}"; exit 1; }
    require_container

    echo "WARNING: this replaces the databases contained in ${file}."
    read -r -p "Type 'restore' to continue: " answer
    [ "${answer}" = "restore" ] || { echo "Aborted."; exit 1; }

    # Connected sessions of the API would block DROP DATABASE.
    echo "Stopping file4base-api during the restore ..."
    docker stop file4base-api >/dev/null 2>&1 || true

    gunzip -c "${file}" | docker exec -i "${CONTAINER}" psql -U "${DB_USER}" -d postgres -v ON_ERROR_STOP=0 -q >/dev/null

    docker start file4base-api >/dev/null 2>&1 || true
    echo "Restore finished from: ${file}"
}

list() {
    ls -lh "${BACKUP_DIR}"/*.sql.gz 2>/dev/null || echo "No backups in ${BACKUP_DIR}"
}

case "${1:-}" in
    backup)  backup ;;
    restore) restore "${2:-}" ;;
    list)    list ;;
    *)       usage ;;
esac
