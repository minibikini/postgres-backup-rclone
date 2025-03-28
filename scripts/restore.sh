#!/bin/bash
set -euo pipefail

# Default values
: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=postgres}"
: "${POSTGRES_DATABASE:=postgres}"
: "${BUCKET_NAME:=backups}"

# Get backup file from argument or use latest
if [ $# -eq 1 ]; then
    BACKUP_FILE="$1"
else
    echo "No backup file specified, getting latest backup..."

    # List files, filter for SQL backup files, sort by filename, and get the newest
    # S3 listing requires different syntax than local file listing
    BACKUP_FILE=$(rclone lsf "remote:${BUCKET_NAME}" --include "*.sql.gz" | sort -r | head -n 1)

    if [ -z "$BACKUP_FILE" ]; then
        echo "ERROR: No backup files found in remote:${BUCKET_NAME}" >&2
        exit 1
    fi

    echo "Latest backup file: ${BACKUP_FILE}"
fi

# Check if backup exists in S3
echo "Checking if backup exists: remote:${BUCKET_NAME}/${BACKUP_FILE}"
if ! rclone lsf "remote:${BUCKET_NAME}/${BACKUP_FILE}" >/dev/null 2>&1; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}" >&2
    exit 1
fi

# Test database connection before starting restore
echo "Testing database connection..."
if ! PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -c '\q' >/dev/null 2>&1; then
    echo "ERROR: Could not connect to PostgreSQL database" >&2
    exit 1
fi

echo "Starting PostgreSQL restore process..."

# Stream restore directly from S3 to PostgreSQL
echo "Restoring ${BACKUP_FILE} to database ${POSTGRES_DATABASE}"
if ! rclone cat "remote:${BUCKET_NAME}/${BACKUP_FILE}" | gunzip | PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE"; then
    echo "ERROR: Restore failed" >&2
    exit 1
fi

echo "Restore complete"
