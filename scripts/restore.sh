#!/bin/bash
set -euo pipefail

# Validate command line arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-filename>" >&2
    echo "Example: $0 2024-03-24T12:00:00Z.sql.gz" >&2
    exit 1
fi

BACKUP_FILE="$1"

# Default values
: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=postgres}"
: "${POSTGRES_DB:=postgres}"
: "${BUCKET_NAME:=backups}"


# Check if backup exists in S3
echo "Checking if backup exists: s3:${BUCKET_NAME}/${BACKUP_FILE}"
if ! rclone lsf "s3:${BUCKET_NAME}/${BACKUP_FILE}" >/dev/null 2>&1; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}" >&2
    exit 1
fi

# Test database connection before starting restore
echo "Testing database connection..."
if ! PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\q' >/dev/null 2>&1; then
    echo "ERROR: Could not connect to PostgreSQL database" >&2
    exit 1
fi

echo "Starting PostgreSQL restore process..."

# Stream restore directly from S3 to PostgreSQL
echo "Restoring ${BACKUP_FILE} to database ${PG_DATABASE}"
if ! rclone cat "remote:${BUCKET_NAME}/${BACKUP_FILE}" | \
     gunzip | \
     PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB"; then
    echo "ERROR: Restore failed" >&2
    exit 1
fi

echo "Restore complete"
