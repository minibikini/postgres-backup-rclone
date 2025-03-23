FROM rclone/rclone:latest

# Reset the entrypoint
ENTRYPOINT []

# Install PostgreSQL 15 client
RUN apk add --no-cache postgresql15-client

# Copy backup and restore scripts
COPY backup.sh restore.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh

# Validate installation
RUN pg_dump --version && rclone version

# Default command
CMD ["sh"]
