FROM rclone/rclone:latest

# Install bash for better script support
RUN apk add --no-cache bash tzdata

# Set timezone (optional, change as needed)
ENV TZ=Asia/Taipei

# Create app directory
WORKDIR /app

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Default environment variables
ENV SYNC_INTERVAL=60
ENV RCLONE_SOURCE=onedrive:
ENV RCLONE_DEST=gdrive:OneDrive-Backup
ENV RCLONE_TRANSFERS=4

# Health check
HEALTHCHECK --interval=5m --timeout=30s --start-period=10s --retries=3 \
    CMD pgrep -f "rclone" > /dev/null || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
