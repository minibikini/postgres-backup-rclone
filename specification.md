### **PostgreSQL Backup/Restore System Specification**

**Version:** 1.0
**Objective:** Automate PostgreSQL database backups/restores using Docker, `rclone`, and S3-compatible storage.

---

### **1. Functional Requirements**

#### **Core Features**

- **Scheduled Backups**: Execute daily backups (configurable via cron syntax).
- **Manual Triggers**: Run backups/restores via CLI commands.
- **Restore Options**: Restore from latest backup or specific timestamp.
- **S3 Integration**: Stream backups directly to/from S3-compatible storage.
- **No Local Storage**: Avoid intermediate files; stream via pipes.

#### **Non-Functional Requirements**

- **Reliability**: Failures in backup/restore pipelines must halt execution and log errors.
- **Portability**: Compatible with PostgreSQL 15+ and major S3 providers (AWS, MinIO, etc.).
- **Seamless Integration**: Work alongside existing Docker Compose setups.

---

### **2. Architecture & Components**

#### **System Diagram**

```
[Docker Compose]
├── PostgreSQL Service (v15)
├── Backup Service (Custom Image)
│   ├── rclone + postgresql-client
│   ├── Backup Script (backup.sh)
│   └── Restore Script (restore.sh)
└── S3 Storage (External/Internal e.g., MinIO)
```

#### **Custom Docker Image**

- **Base Image**: `rclone/rclone:latest` (Alpine-based).
- **Dependencies**:
  - `postgresql15-client` (version matches target PostgreSQL).
  - Scripts: `backup.sh`, `restore.sh` (mounted or baked into image).
- **Build Command**:
  ```dockerfile
  FROM rclone/rclone:latest
  RUN apk add --no-cache postgresql15-client
  COPY scripts/* /usr/local/bin/
  RUN chmod +x /usr/local/bin/backup /usr/local/bin/restore
  ```

---

### **3. Data Flow & Handling**

#### **Backup Process**

1. **Trigger**: Cron schedule or manual command.
2. **Dump**: `pg_dump` streams database to stdout.
3. **Compress**: Pipe output to `gzip`.
4. **Upload**: Stream compressed data to S3 via `rclone rcat`.
5. **Naming**: `{POSTGRES_DB}_{TIMESTAMP}.sql.gz` (e.g., `appdb_2023-10-05T12:00:00Z.sql.gz`).

#### **Restore Process**

1. **List Backups**: Fetch available backups from S3.
2. **Download**: Stream selected backup via `rclone cat`.
3. **Decompress**: Pipe to `gunzip`.
4. **Restore**: Pipe to `psql` for execution.

---

### **4. Error Handling & Logging**

#### **Failure Modes**

- **PostgreSQL Unreachable**: Script exits with error code.
- **Invalid S3 Credentials**: `rclone` fails, logs error.
- **Corrupted Backup**: `pg_restore`/`psql` errors during restore.

#### **Mitigation Strategies**

- **`set -eo pipefail`**: Scripts exit on first error in any pipeline stage.
- **Explicit Logging**: Cron jobs pipe output to `logger -t pg_backup`.
- **Pre-Restore Validation**:
  ```bash
  # restore.sh
  if ! rclone ls "s3:${RCLONE_S3_BUCKET}/$1" > /dev/null; then
    echo "Error: Backup file $1 not found."
    exit 1
  fi
  ```

#### **Logging**

- **Cron Logs**: Access via `docker compose logs backup | grep "pg_backup"`.
- **Audit Trail**: Backup filenames include timestamps for traceability.

---

### **5. Docker Compose Integration**

#### **Service Definition**

```yaml
services:
  backup:
    image: ghcr.io/minibikini/postgres-backup-rclone:15
    environment:
      # PostgreSQL Connection
      POSTGRES_HOST: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}

      # Rclone S3 Configuration
      RCLONE_S3_PROVIDER: "Other"
      RCLONE_S3_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      RCLONE_S3_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      RCLONE_S3_BUCKET: ${S3_BUCKET}
      RCLONE_S3_ENDPOINT: ${S3_HOST}
      RCLONE_S3_REGION: "" # Optional

      # Schedule (cron syntax)
      BACKUP_SCHEDULE: "0 0 * * *" # Daily at midnight
    networks:
      - internal
    depends_on:
      postgres:
        condition: service_healthy
    command: >
      sh -c "echo '$${BACKUP_SCHEDULE} /usr/local/bin/backup 2>&1 | logger -t pg_backup'
      | crontab - && crond -f"
```

#### **Key Dependencies**

- **Shared Network**: `internal` network for PostgreSQL access.
- **Health Checks**: Backup service waits for `postgres` to be healthy.

---

### **6. Testing Plan**

#### **A. Unit Tests (Isolated Scripts)**

- **Tool**: `bats-core` (Bash Automated Testing System).
- **Test Cases**:
  1. `backup.sh` generates a valid backup and uploads to S3.
  2. `restore.sh` fetches and restores a backup successfully.
  3. Invalid credentials trigger appropriate errors.

#### **B. Integration Tests (Full Workflow)**

- **Tool**: Docker Compose + MinIO (local S3 emulation).
- **Steps**:
  1. Deploy test stack with PostgreSQL, MinIO, and backup service.
  2. Insert test data into PostgreSQL.
  3. Trigger backup and verify S3 upload.
  4. Delete PostgreSQL data, restore from backup, and validate data integrity.

#### **C. Image Testing**

- **Validation**:
  ```bash
  docker run --rm yourimage /usr/local/bin/backup --version
  # Verify rclone, pg_dump, psql are executable.
  ```

---

### **7. Environment Variables**

| Variable             | Purpose                            | Example             |
| -------------------- | ---------------------------------- | ------------------- |
| `POSTGRES_HOST`      | PostgreSQL hostname                | `postgres`          |
| `POSTGRES_USER`      | Database user                      | `postgres`          |
| `POSTGRES_PASSWORD`  | Database password                  | `secret`            |
| `RCLONE_S3_PROVIDER` | S3 provider (e.g., `AWS`, `Other`) | `Other`             |
| `RCLONE_S3_ENDPOINT` | S3 endpoint URL                    | `http://minio:9000` |

---

### **8. Deliverables**

1. **Docker Image**:
   - Published to a registry (Docker Hub, GHCR) with version tags.
2. **Scripts**:
   - `backup.sh`, `restore.sh` (streaming logic, error handling).
3. **Example `docker-compose.yml`**:
   - Demonstrates integration with PostgreSQL and S3.
4. **Test Suite**:
   - Bats tests, Docker Compose integration tests.

---

### **9. Implementation Steps**

1. Build custom Docker image.
2. Integrate `backup` service into existing Docker Compose.
3. Configure S3 credentials via environment variables.
4. Test backup/restore workflow manually.
5. Deploy and validate cron scheduling.

---

**Next Step for Developer:**

- Clone the attached repository, review scripts, and begin implementation using the above spec.
- Priority: Ensure streaming backup/restore works with the existing PostgreSQL setup.
