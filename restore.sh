#!/bin/bash
set -euo pipefail

# Validate command line arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-filename>" >&2
    echo "Example: $0 2024-03-24T12:00:00Z.dump.gz" >&2
    exit 1
fi

BACKUP_FILE="$1"

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
    echo "ERROR: Missing required environment variables, aborting restore" >&2
    exit 1
fi

# Check if backup exists in S3
echo "Checking if backup exists: ${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_FILE}"
if ! rclone lsf "${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_FILE}" >/dev/null 2>&1; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}" >&2
    exit 1
fi

# Test database connection before starting restore
echo "Testing database connection..."
if ! PGPASSWORD="${PGPASSWORD:-}" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -c '\q' >/dev/null 2>&1; then
    echo "ERROR: Could not connect to PostgreSQL database" >&2
    exit 1
fi

echo "Starting PostgreSQL restore process..."

# Stream restore directly from S3 to PostgreSQL
echo "Restoring ${BACKUP_FILE} to database ${PG_DATABASE}"
if ! rclone cat "${RCLONE_REMOTE}:${RCLONE_PATH}/${BACKUP_FILE}" | \
     gunzip | \
     PGPASSWORD="${PGPASSWORD:-}" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" $PG_EXTRA_OPTS; then
    echo "ERROR: Restore failed" >&2
    exit 1
fi

echo "Restore complete"
