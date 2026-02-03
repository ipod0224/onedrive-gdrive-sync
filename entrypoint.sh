#!/bin/sh
set -e

CONFIG_DIR="/config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"

# Create config directory
mkdir -p "${CONFIG_DIR}"

# Inject rclone config from environment variable
# Supports both Base64 encoded (RCLONE_CONF_BASE64) and plain text (RCLONE_CONF_CONTENT)
if [ -n "${RCLONE_CONF_BASE64}" ]; then
    echo "Decoding Base64 rclone config..."
    echo "${RCLONE_CONF_BASE64}" | base64 -d > "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
    echo "Config file created at ${CONFIG_FILE}"
elif [ -n "${RCLONE_CONF_CONTENT}" ]; then
    echo "Injecting rclone config from environment..."
    printf '%s' "${RCLONE_CONF_CONTENT}" > "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
    echo "Config file created at ${CONFIG_FILE}"
else
    echo "ERROR: RCLONE_CONF_BASE64 or RCLONE_CONF_CONTENT environment variable is not set!"
    echo "Please set it in Zeabur dashboard."
    exit 1
fi

# Configuration
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"  # Default: 60 seconds
SOURCE="${RCLONE_SOURCE:-onedrive:}"
DEST="${RCLONE_DEST:-gdrive:OneDrive-Backup}"
TRANSFERS="${RCLONE_TRANSFERS:-4}"

echo "========================================="
echo "OneDrive -> Google Drive Sync Service"
echo "========================================="
echo "Source:    ${SOURCE}"
echo "Dest:      ${DEST}"
echo "Interval:  ${SYNC_INTERVAL}s"
echo "Transfers: ${TRANSFERS}"
echo "========================================="

# Test connection first
echo "Testing connections..."
if ! rclone lsd "${SOURCE}" --config "${CONFIG_FILE}" > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to source (${SOURCE})"
    echo "Please check your rclone config."
    exit 1
fi
echo "Source OK: ${SOURCE}"

if ! rclone lsd "${DEST%:*}:" --config "${CONFIG_FILE}" > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to destination (${DEST%:*}:)"
    echo "Please check your rclone config."
    exit 1
fi
echo "Destination OK: ${DEST%:*}:"
echo "========================================="

# Sync loop
SYNC_COUNT=0
while true; do
    SYNC_COUNT=$((SYNC_COUNT + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo "[${TIMESTAMP}] Starting sync #${SYNC_COUNT}..."

    if rclone sync "${SOURCE}" "${DEST}" \
        --config "${CONFIG_FILE}" \
        --transfers "${TRANSFERS}" \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        --low-level-retries 10 \
        --stats 30s \
        --stats-one-line \
        -v; then
        echo "[${TIMESTAMP}] Sync #${SYNC_COUNT} completed successfully"
    else
        echo "[${TIMESTAMP}] Sync #${SYNC_COUNT} failed with error code $?"
    fi

    echo "Next sync in ${SYNC_INTERVAL} seconds..."
    sleep "${SYNC_INTERVAL}"
done
