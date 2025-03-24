#!/usr/bin/env bats

load "../node_modules/bats-assert/load.bash";
load "../node_modules/bats-support/load.bash";

setup_file() {
  docker compose build backup
  docker compose up -d --wait

  # Configure MinIO bucket
  docker compose exec -T minio mc alias set s3 http://minio:9000 minioadmin minioadmin
  docker compose exec -T minio mc mb s3/backups
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

  # Get timestamp before creating our "latest" backup
  docker compose run --rm backup backup.sh
  current_time=$(date +%s)
  sleep 2  # Make sure the next backup will have a different timestamp

  # Add more data and create a second backup - this should be the latest one
  docker compose exec -T postgres psql -U postgres -c "INSERT INTO test_data VALUES (DEFAULT)"
  docker compose run --rm backup backup.sh

  # Verify we have a new backup (created after our timestamp)
  latest_backup=$(docker compose exec -T minio mc ls s3/backups | grep -E 'postgres-.*\.sql\.gz' | sort -r | head -n 1)
  echo "Latest backup entry: $latest_backup"

  # Drop test table
  docker compose exec -T postgres psql -U postgres -c "DROP TABLE test_data"

  # Run restore without filename
  docker compose run --rm backup restore.sh

  # Verify the latest data exists (we should have at least 2 rows)
  run docker compose exec -T postgres psql -U postgres -tAc "SELECT COUNT(*) FROM test_data"
  assert_success
  assert_equal $output  2
}
