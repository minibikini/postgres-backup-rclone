#!/bin/bash
set -euo pipefail

# Default values
: "${PG_HOST:=localhost}"
: "${PG_PORT:=5432}"
: "${PG_USER:=postgres}"
: "${PG_DATABASE:=postgres}"
: "${RCLONE_REMOTE:=remote}"
: "${RCLONE_PATH:=backups}"

# Validate required environment variables
missing_vars=0
for var in PG_HOST PG_PORT PG_USER PG_DATABASE RCLONE_REMOTE RCLONE_PATH; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: ${var} environment variable is not set" >&2
    missing_vars=$((missing_vars + 1))
  fi
done

if [[ $missing_vars -gt 0 ]]; then
  echo "ERROR: Missing required environment variables, aborting backup" >&2
  exit 1
fi

# Generate ISO8601 timestamp for backup filename
BACKUP_NAME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Starting PostgreSQL backup process..."

# Create and upload backup in a pipeline
echo "Creating and uploading backup to ${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_NAME}.dump.gz"
if ! pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -F c $PG_EXTRA_OPTS 2>/dev/stderr | \
     gzip | \
     rclone rcat "${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_NAME}.dump.gz"; then
  echo "ERROR: Backup failed" >&2
  exit 1
fi

echo "Backup complete: ${BACKUP_NAME}.dump.gz"
