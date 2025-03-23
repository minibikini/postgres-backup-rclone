#!/bin/sh
set -e

# Default values
: "${PG_HOST:=localhost}"
: "${PG_PORT:=5432}"
: "${PG_USER:=postgres}"
: "${PG_DATABASE:=postgres}"
: "${RCLONE_REMOTE:=remote}"
: "${RCLONE_PATH:=backups}"
: "${BACKUP_FILE:?BACKUP_FILE environment variable is required}"

echo "Starting PostgreSQL restore process..."

# Download from remote
echo "Downloading ${BACKUP_FILE} from ${RCLONE_REMOTE}:${RCLONE_PATH}"
rclone copy "${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_FILE}" "/tmp/"

# Restore backup
echo "Restoring database ${PG_DATABASE} from ${BACKUP_FILE}"
pg_restore -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" $PG_EXTRA_OPTS "/tmp/${BACKUP_FILE}"

# Cleanup
rm -f "/tmp/${BACKUP_FILE}"

echo "Restore complete"
