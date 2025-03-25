#!/usr/bin/env bats

load "../node_modules/bats-assert/load.bash";
load "../node_modules/bats-support/load.bash";

setup_file() {
  docker compose build backup
  docker compose up -d --wait

  # Configure MinIO bucket, ignore error if bucket exists
  docker compose exec -T minio mc alias set s3 http://minio:9000 minioadmin minioadmin
  docker compose exec -T minio mc mb s3/backups || true
}

teardown_file() {
  docker compose down -v --remove-orphans
}

@test "Container starts and services are healthy" {
  run docker compose ps --services --filter 'status=running'
  assert_output - <<EOF
backup
minio
postgres
EOF
}

@test "Manual backup creates object in MinIO" {
  # Create test data
  docker compose exec -T postgres psql -U postgres -c "CREATE TABLE test_data (id SERIAL PRIMARY KEY)"

  # Run backup
  docker compose run --rm backup backup.sh

  # Check MinIO for backup file
  run docker compose exec -T minio mc find s3/backups --name "*.sql.gz"
  assert_success
  assert_output --regexp 'postgres-[0-9]{4}-.*\.sql\.gz'
}

@test "Restore from backup works correctly with explicit filename" {
  # Get latest backup name
  backup_name=$(docker compose exec -T minio mc ls s3/backups | awk '/postgres/ {print $NF}' | tail -1)

  echo $(docker compose exec -T minio mc ls s3/backups)

  # Drop test table
  docker compose exec -T postgres psql -U postgres -c "DROP TABLE test_data"

  # Run restore
  docker compose run --rm backup restore.sh $backup_name

  # Verify table exists after restore
  run docker compose exec -T postgres psql -U postgres -tAc "SELECT to_regclass('public.test_data')"
  assert_success
  assert_output 'test_data'
}

@test "Restore from latest backup works correctly without filename" {
  # Drop and recreate test table to start fresh
  docker compose exec -T postgres psql -U postgres -c "DROP TABLE IF EXISTS test_data; CREATE TABLE test_data (id SERIAL PRIMARY KEY)"

  # Create first backup with initial data
  docker compose exec -T postgres psql -U postgres -c "INSERT INTO test_data VALUES (DEFAULT)"
  docker compose run --rm backup backup.sh

  # Get timestamp from MinIO container just before creating new backup
  current_time=$(docker compose exec -T minio date +%s)
  sleep 2  # Ensure timestamp separation within MinIO's storage

  # Add more data and create second backup
  docker compose exec -T postgres psql -U postgres -c "INSERT INTO test_data VALUES (DEFAULT)"
  docker compose run --rm backup backup.sh

  # Get ISO8601 timestamp using local jq
  minio_json=$(docker compose exec -T minio mc ls --json s3/backups)
  latest_backup_iso=$(echo "$minio_json" | jq -rs 'map(select(.key | endswith(".sql.gz"))) | sort_by(.lastModified) | reverse | .[0].lastModified')

  # Convert to Unix timestamp using MinIO container's date command
  backup_timestamp=$(docker compose exec -T minio date -d "$latest_backup_iso" +%s)

  # Validate comparison
  [ -n "$latest_backup_iso" ] || { echo "No backup found"; return 1; }
  [ -n "$backup_timestamp" ] || { echo "Invalid timestamp conversion"; return 1; }
  assert [ "$backup_timestamp" -gt "$current_time" ]

  # Drop test table
  docker compose exec -T postgres psql -U postgres -c "DROP TABLE test_data"

  # Run restore without filename
  docker compose run --rm backup restore.sh

  # Verify the latest data exists (we should have at least 2 rows)
  run docker compose exec -T postgres psql -U postgres -tAc "SELECT COUNT(*) FROM test_data"
  assert_success
  assert_equal $output  2
}

@test "Scheduled backup via cron creates object in MinIO" {
  # Set backup schedule to run every minute
  export BACKUP_SCHEDULE="* * * * *"

  # Recreate backup service with new schedule
  docker compose up -d --force-recreate backup

  # Create test data
  docker compose exec -T postgres psql -U postgres -c "DROP TABLE IF EXISTS test_data; CREATE TABLE test_data (id SERIAL PRIMARY KEY)"
  docker compose exec -T postgres psql -U postgres -c "INSERT INTO test_data VALUES (DEFAULT)"

  # Wait for cron to trigger (70 seconds to ensure one run)
  sleep 70

  # Check MinIO for backup file from the last minute
  run docker compose exec -T minio mc find s3/backups --name "*.sql.gz" --newer-than 2m
  assert_success
  assert_output --regexp 'postgres-[0-9]{4}-.*\.sql\.gz'
}
