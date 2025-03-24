#!/bin/bash
set -euo pipefail

# Default values
: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=postgres}"
: "${POSTGRES_DATABASE:=postgres}"
: "${BUCKET_NAME:=backups}"

# Generate ISO8601 timestamp for backup filename
BACKUP_NAME=${POSTGRES_DATABASE}-$(date -u +"%Y-%m-%d-%H-%M-%S")

echo "Starting PostgreSQL backup process..."

# Create and upload backup in a pipeline
echo "Creating and uploading backup to s3:${BUCKET_NAME}/${BACKUP_NAME}.sql.gz"

if ! PGPASSWORD=$POSTGRES_PASSWORD pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" 2>/dev/stderr | \
    cat | \
    gzip | \
    rclone --progress -v rcat "remote:${BUCKET_NAME}/${BACKUP_NAME}.sql.gz"; then
  echo "ERROR: Backup failed" >&2
  exit 1
fi

echo "Backup complete: ${BACKUP_NAME}.sql.gz"
