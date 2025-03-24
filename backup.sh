#!/bin/bash
set -euo pipefail

# Default values
: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=postgres}"
: "${RCLONE_S3_BUCKET:=backups}"

# Validate required environment variables
missing_vars=0
for var in POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_DB RCLONE_S3_BUCKET; do
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
echo "Creating and uploading backup to s3:${RCLONE_S3_BUCKET}/${BACKUP_NAME}.sql.gz"
if ! PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=plain --no-owner --no-acl 2>/dev/stderr | \
     gzip | \
     rclone rcat "s3:${RCLONE_S3_BUCKET}/${BACKUP_NAME}.sql.gz"; then
  echo "ERROR: Backup failed" >&2
  exit 1
fi

echo "Backup complete: ${BACKUP_NAME}.dump.gz"
