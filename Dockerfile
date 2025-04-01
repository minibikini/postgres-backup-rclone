FROM rclone/rclone:latest

# Reset the entrypoint
ENTRYPOINT []

RUN apk add --no-cache bash

# Add build argument for PostgreSQL version with latest (17) as default
ARG POSTGRES_VERSION=17

# Install PostgreSQL client
RUN apk add --no-cache postgresql${POSTGRES_VERSION}-client || \
    apk add --no-cache postgresql-client

# Copy backup and restore scripts
COPY scripts/backup.sh scripts/restore.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh

# Validate installation
RUN pg_dump --version && rclone version

# Default command - Using bash instead of sh
CMD ["bash"]

LABEL org.opencontainers.image.source=https://github.com/minibikini/postgres-backup-rclone
LABEL org.opencontainers.image.description="Backup and restore PostgreSQL databases using Rclone"
LABEL org.opencontainers.image.licenses=MIT
