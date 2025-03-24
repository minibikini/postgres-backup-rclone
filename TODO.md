# PostgreSQL Backup/Restore System Checklist

## **Docker Image Setup**

- [ ] Create Dockerfile with `rclone/rclone` base
  - Verify: `docker build` succeeds without errors
- [ ] Install `postgresql15-client` in image
  - Verify: `docker run --rm image pg_dump --version` shows v15
- [ ] Copy backup/restore scripts to `/usr/local/bin`
  - Verify: `docker run --rm image ls /usr/local/bin` shows scripts
- [ ] Make scripts executable in Dockerfile
  - Verify: `docker run --rm image sh -c "test -x /usr/local/bin/backup.sh"`

## **Backup Script Implementation**

- [ ] Implement core streaming pipeline:
      `pg_dump | gzip | rclone rcat`
  - Verify: Creates S3 object with correct name pattern
- [ ] Add timestamp generation (ISO8601 format)
  - Verify: Filenames contain `2024-03-15T14:30:00Z` format
- [ ] Validate required environment variables:
      `POSTGRES_HOST, POSTGRES_USER, POSTGRES_DB, BUCKET_NAME`
  - Verify: Script exits with error if any are missing
- [ ] Implement connection testing pre-flight check
  - Verify: Script fails fast if PostgreSQL is unreachable

## **Restore Script Implementation**

- [ ] Implement core restore pipeline:
      `rclone cat | gunzip | psql`
  - Verify: Can restore test database from backup
- [ ] Add backup file existence check
  - Verify: `restore.sh invalid_file` exits with error
- [ ] Add database connection validation
  - Verify: Script fails if PostgreSQL credentials are wrong
- [ ] Implement argument validation (requires filename)
  - Verify: `restore.sh` without args shows usage

## **Docker Compose Integration**

- [ ] Create backup service definition
  - Verify: `docker compose up backup` starts successfully
- [ ] Configure environment variables:
  ```yaml
  POSTGRES_HOST, POSTGRES_USER, POSTGRES_PASSWORD
  RCLONE_S3_* variables
  BACKUP_SCHEDULE
  ```
  - Verify: Variables propagate to container
- [ ] Implement cron scheduling
  - Verify: `docker exec backup crontab -l` shows schedule
- [ ] Set up network dependencies
  - Verify: Backup container can ping PostgreSQL host

## **Error Handling & Logging**

- [ ] Add `set -euo pipefail` to all scripts
  - Verify: Failed command in pipeline exits script
- [ ] Implement trap for cleanup operations
  - Verify: Temporary files removed on script exit
- [ ] Add error context messages to stderr
  - Verify: `PG_PASSWORD=wrong ./backup.sh` shows meaningful error
- [ ] Set up logging via `logger`
  - Verify: `docker logs backup` shows backup attempts

## **Testing & Validation**

- [ ] Create BATS test framework
  - Verify: `bats test/unit.bats` runs test suite
- [ ] Implement integration test with MinIO
  - Verify: Full backup/restore cycle succeeds
- [ ] Test backup schedule simulation
  - Verify: Changing cron to `*/5 * * * *` triggers 5-min backups
- [ ] Test edge cases:
  - [ ] 1GB+ database backup
  - [ ] Special characters in database name
  - [ ] S3 bucket with existing backups

## **Deployment Preparation**

- [ ] Create example docker-compose.yml
  - Verify: Fresh clone can start system with env vars
- [ ] Document required permissions:
  - PostgreSQL user needs SUPERUSER for backup
  - S3 bucket needs write access
- [ ] Set up healthchecks for PostgreSQL
  - Verify: `depends_on: condition: service_healthy`
- [ ] Create monitoring dashboard basics
  - Verify: Last backup timestamp metric exists

## **Documentation**

- [ ] Write usage guide:

  ```bash
  # Manual backup
  docker compose run backup /usr/local/bin/backup.sh

  # Restore specific backup
  docker compose run backup /usr/local/bin/restore.sh filename.sql.gz
  ```

- [ ] Create troubleshooting section
  - Common errors: Connection issues, S3 permissions
- [ ] Add version compatibility matrix
  - Tested PostgreSQL versions, S3 providers
- [ ] Document retention policy recommendations

## **Future Enhancements**

- [ ] Backup encryption support
- [ ] Automatic retention policy (delete old backups)
- [ ] Multi-database backup support
- [ ] Prometheus metrics endpoint
- [ ] Slack/Email notifications
- [ ] Point-in-time recovery (WAL archiving)

**Verification Workflow**:

1. Set up test environment with:
   ```bash
   docker compose up -d postgres minio
   docker compose exec postgres psql -c "CREATE DATABASE testdb"
   ```
2. Run through checklist items sequentially
3. After each task:
   - Run relevant test command
   - Check exit code (`echo $?`)
   - Inspect logs/output for expected behavior

**Final Sign-off**:

- [ ] Full backup/restore cycle validated with production-like data
- [ ] Security review completed (credentials handling, permissions)
- [ ] Performance tested with maximum expected database size
