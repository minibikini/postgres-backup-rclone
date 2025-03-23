# Step-by-Step Implementation Blueprint

## **Phase 1: Core Components**
### **1.1 Docker Image Setup**

```text
Create a Dockerfile that:
- Uses `rclone/rclone:latest` as base
- Installs `postgresql15-client` via Alpine package manager
- Copies `backup.sh` and `restore.sh` to `/usr/local/bin`
- Makes scripts executable
- Validates installation of `pg_dump` and `rclone`

Test command:
`docker build -t pgbackup . && docker run --rm pgbackup sh -c "pg_dump --version && rclone version"`
```

### **1.2 Backup Script (Stream to S3)**
```text
Implement backup.sh with:
- `set -euo pipefail` for strict error handling
- Environment variable validation (POSTGRES_* vars)
- Backup filename generation with ISO8601 timestamp
- Pipeline: pg_dump → gzip → rclone rcat
- Error logging to stderr

Test case:
`POSTGRES_HOST=localhost ./backup.sh` should fail with connection error (expected behavior)`
```

### **1.3 Restore Script (Stream from S3)**
```text
Implement restore.sh with:
- Argument validation for backup filename
- Pipeline: rclone cat → gunzip → psql
- Pre-check for backup existence in S3
- Database connection validation

Test case:
`./restore.sh invalid_filename.sql.gz` should exit with "Backup not found" error`
```

---

## **Phase 2: Docker Integration**
### **2.1 Docker Compose Service**
```text
Create docker-compose.yml snippet:
- Backup service using built image
- Environment variables for PostgreSQL/S3
- Shared network with PostgreSQL
- Healthcheck dependency
- Cron scheduling implementation

Test command:
`docker compose up -d backup` should show crond running`
```

### **2.2 Environment Validation**
```text
Add startup check to backup.sh:
- Verify PostgreSQL is reachable via `pg_isready`
- Validate S3 connectivity with `rclone lsd s3:${RCLONE_S3_BUCKET}`
- Exit with clear error messages before backup attempts
```

---

## **Phase 3: Error Handling & Logging**
### **3.1 Pipeline Error Trapping**
```text
Enhance scripts with:
- Trap signals (EXIT, ERR) for cleanup
- Temporary file cleanup on exit
- Exit code propagation through pipes
- Error context messages (e.g., "Failed during S3 upload")
```

### **3.2 Structured Logging**
```text
Implement logging:
- JSON-formatted logs with timestamps
- Severity levels (INFO, ERROR)
- Log redirection to stdout/stderr
- Correlation IDs for backup/restore operations
```

---

## **Phase 4: Testing Infrastructure**
### **4.1 Bats Test Framework**
```text
Create test/unit.bats with:
- Mock PostgreSQL container
- MinIO test instance
- Test cases for backup/restore lifecycle
- Negative tests (invalid credentials, missing backups)
```

### **4.2 CI Pipeline**
```text
Add GitHub Actions workflow:
- Build Docker image
- Run unit tests with Bats
- Integration test with Docker Compose
- Vulnerability scanning with Trivy
```

---

## **Phase 5: Deployment & Validation**
### **5.1 Manual Test Checklist**
```text
Validation steps:
1. Start PostgreSQL + MinIO containers
2. Insert test data `CREATE TABLE backup_test (id SERIAL)`
3. Run manual backup
4. Verify S3 object creation
5. Drop table + restore
6. Verify table existence post-restore
```

### **5.2 Monitoring Integration**
```text
Add:
- Prometheus metrics endpoint
- Backup success/failure counters
- Duration histograms
- S3 bucket size metrics
```

---

# Iterative Implementation Prompts

## **Prompt 1: Docker Image Foundation**
```dockerfile
FROM rclone/rclone:latest
RUN apk add --no-cache postgresql15-client
COPY backup.sh restore.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh
HEALTHCHECK --interval=30s CMD pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER
```

## **Prompt 2: Backup Script Core**
```bash
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILENAME="${POSTGRES_DB}_${TIMESTAMP}.sql.gz"

pg_dump -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  | gzip \
  | rclone rcat "s3:${RCLONE_S3_BUCKET}/${FILENAME}"
```

## **Prompt 3: Restore Script Core**
```bash
#!/bin/bash
set -euo pipefail

BACKUP_FILE="$1"

rclone cat "s3:${RCLONE_S3_BUCKET}/${BACKUP_FILE}" \
  | gunzip \
  | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

## **Prompt 4: Docker Compose Integration**
```yaml
services:
  backup:
    image: pgbackup
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
      RCLONE_S3_BUCKET: backups
      RCLONE_S3_ENDPOINT: http://minio:9000
    command: >
      sh -c "echo '$${BACKUP_SCHEDULE} /usr/local/bin/backup.sh 2>&1 | logger -t pgbackup'
      | crontab - && crond -f"
```

## **Prompt 5: Error Handling Upgrade**
```bash
# In backup.sh
if ! pg_isready -h "$POSTGRES_HOST" -U "$POSTGRES_USER"; then
  echo "PostgreSQL unreachable at $POSTGRES_HOST" >&2
  exit 1
fi

if ! rclone lsd "s3:${RCLONE_S3_BUCKET}" >/dev/null 2>&1; then
  echo "S3 bucket inaccessible" >&2
  exit 1
fi
```

## **Prompt 6: Final Integration**
```bash
# Test command sequence
docker compose up -d postgres minio
docker compose exec postgres psql -U postgres -c "CREATE TABLE test (id SERIAL)"
docker compose run --rm backup /usr/local/bin/backup.sh
docker compose exec postgres psql -U postgres -c "DROP TABLE test"
docker compose run --rm backup /usr/local/bin/restore.sh $(rclone ls s3:backups | awk '{print $2}')
```

Each prompt builds on previous components while maintaining standalone testability. Next steps would focus on expanding monitoring and test coverage while hardening security practices.