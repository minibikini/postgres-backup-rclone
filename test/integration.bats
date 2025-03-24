#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

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
  docker compose run --rm backup /usr/local/bin/backup.sh

  # Check MinIO for backup file
  run docker compose exec -T minio mc find s3/backups --name "*.sql.gz"
  assert_success
  assert_output --regexp 'postgres-[0-9]{4}-.*\.sql\.gz'
}

@test "Restore from backup works correctly" {
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
