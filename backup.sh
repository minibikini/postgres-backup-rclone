#!/bin/sh
set -e

# Default values
: "${PG_HOST:=localhost}"
: "${PG_PORT:=5432}"
: "${PG_USER:=postgres}"
: "${PG_DATABASE:=postgres}"
: "${RCLONE_REMOTE:=remote}"
: "${RCLONE_PATH:=backups}"
: "${BACKUP_NAME:=$(date +%Y%m%d_%H%M%S)}"

echo "Starting PostgreSQL backup process..."

# Create backup
pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -F c -f "/tmp/${BACKUP_NAME}.dump" $PG_EXTRA_OPTS

# Upload to remote
echo "Uploading backup to ${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_NAME}.dump"
rclone copy "/tmp/${BACKUP_NAME}.dump" "${RCLONE_REMOTE}:${RCLONE_PATH}/"

# Cleanup
rm -f "/tmp/${BACKUP_NAME}.dump"

echo "Backup complete: ${BACKUP_NAME}.dump"
