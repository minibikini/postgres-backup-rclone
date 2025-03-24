#!/usr/bin/env bats

setup_file() {
  export COMPOSE_PROJECT_NAME="backup_test_$(date +%s)"
  docker compose build backup
  docker compose up -d --wait postgres minio backup

  # Wait for services to be healthy
  # Add slight delay before checking ports
  sleep 5
  wait_for postgres 5432
  wait_for minio 9000
}

teardown_file() {
  docker compose down -v --remove-orphans
}

wait_for() {
  local host=$1 port=$2
  for _ in {1..30}; do
    if docker compose exec -T $host nc -z localhost $port; then
      return 0
    fi
    sleep 1
  done
  echo "Service $host:$port did not become ready in time"
  exit 1
}

@test "Container starts and services are healthy" {
  # Give containers more time to start
  sleep 3
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
  assert_output --regexp 'postgres_[0-9]{4}-.*\.sql\.gz'
}

@test "Restore from backup works correctly" {
  # Get latest backup name
  backup_name=$(docker compose exec -T minio mc ls s3/backups | awk '/postgres/ {print $NF}' | tail -1)
  
  # Drop test table
  docker compose exec -T postgres psql -U postgres -c "DROP TABLE test_data"
  
  # Run restore
  docker compose run --rm backup /usr/local/bin/restore.sh "$backup_name"
  
  # Verify table exists after restore
  run docker compose exec -T postgres psql -U postgres -tAc "SELECT to_regclass('public.test_data')"
  assert_success
  assert_output 'test_data'
}
