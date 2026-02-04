#!/bin/sh
set -e

CONFIG_DIR="/config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"

# Create config directory
mkdir -p "${CONFIG_DIR}"

# Email notification settings
ALERT_EMAIL="${ALERT_EMAIL:-}"
SENDGRID_API_KEY="${SENDGRID_API_KEY:-}"
ALERT_SENT=0

# Function to send email alert
send_alert() {
    local subject="$1"
    local message="$2"

    if [ -z "${ALERT_EMAIL}" ] || [ -z "${SENDGRID_API_KEY}" ]; then
        echo "WARNING: Email alert not configured (ALERT_EMAIL or SENDGRID_API_KEY missing)"
        return 1
    fi

    echo "Sending alert email to ${ALERT_EMAIL}..."

    curl -s --request POST \
        --url https://api.sendgrid.com/v3/mail/send \
        --header "Authorization: Bearer ${SENDGRID_API_KEY}" \
        --header "Content-Type: application/json" \
        --data "{
            \"personalizations\": [{
                \"to\": [{\"email\": \"${ALERT_EMAIL}\"}]
            }],
            \"from\": {\"email\": \"noreply@zeabur.app\", \"name\": \"OneDrive-GDrive Sync\"},
            \"subject\": \"${subject}\",
            \"content\": [{
                \"type\": \"text/plain\",
                \"value\": \"${message}\"
            }]
        }" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "Alert email sent successfully"
        return 0
    else
        echo "Failed to send alert email"
        return 1
    fi
}

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
echo "Alert:     ${ALERT_EMAIL:-Not configured}"
echo "========================================="

# Test connection first
echo "Testing connections..."

# Test source connection
if ! rclone lsd "${SOURCE}" --config "${CONFIG_FILE}" > /dev/null 2>&1; then
    ERROR_MSG="Cannot connect to source (${SOURCE}). Token may have expired. Please update your rclone config."
    echo "ERROR: ${ERROR_MSG}"
    send_alert "[ALERT] OneDrive Token Expired" "Service: OneDrive-GDrive Sync\nError: ${ERROR_MSG}\nTime: $(date '+%Y-%m-%d %H:%M:%S')\n\nPlease re-authorize OneDrive in rclone and update RCLONE_CONF_BASE64 in Zeabur."
    exit 1
fi
echo "Source OK: ${SOURCE}"

# Test destination connection
if ! rclone lsd "${DEST%:*}:" --config "${CONFIG_FILE}" > /dev/null 2>&1; then
    ERROR_MSG="Cannot connect to destination (${DEST%:*}:). Token may have expired. Please update your rclone config."
    echo "ERROR: ${ERROR_MSG}"
    send_alert "[ALERT] Google Drive Token Expired" "Service: OneDrive-GDrive Sync\nError: ${ERROR_MSG}\nTime: $(date '+%Y-%m-%d %H:%M:%S')\n\nPlease re-authorize Google Drive in rclone and update RCLONE_CONF_BASE64 in Zeabur."
    exit 1
fi
echo "Destination OK: ${DEST%:*}:"
echo "========================================="

# Sync loop
SYNC_COUNT=0
CONSECUTIVE_FAILURES=0
MAX_FAILURES=3

while true; do
    SYNC_COUNT=$((SYNC_COUNT + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo "[${TIMESTAMP}] Starting sync #${SYNC_COUNT}..."

    # Capture sync output for error detection
    SYNC_OUTPUT=$(mktemp)

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
        -v 2>&1 | tee "${SYNC_OUTPUT}"; then
        echo "[${TIMESTAMP}] Sync #${SYNC_COUNT} completed successfully"
        CONSECUTIVE_FAILURES=0
        ALERT_SENT=0
    else
        EXIT_CODE=$?
        echo "[${TIMESTAMP}] Sync #${SYNC_COUNT} failed with error code ${EXIT_CODE}"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))

        # Check for token expiration errors
        if grep -qi "token" "${SYNC_OUTPUT}" && grep -qi "expired\|invalid\|refresh" "${SYNC_OUTPUT}"; then
            if [ "${ALERT_SENT}" -eq 0 ]; then
                ERROR_DETAIL=$(grep -i "token\|expired\|invalid\|auth" "${SYNC_OUTPUT}" | head -5)
                send_alert "[ALERT] Sync Token Expired" "Service: OneDrive-GDrive Sync\nSync #${SYNC_COUNT} failed\nTime: ${TIMESTAMP}\n\nError details:\n${ERROR_DETAIL}\n\nPlease re-authorize in rclone and update RCLONE_CONF_BASE64 in Zeabur."
                ALERT_SENT=1
            fi
        fi

        # Alert after consecutive failures
        if [ "${CONSECUTIVE_FAILURES}" -ge "${MAX_FAILURES}" ] && [ "${ALERT_SENT}" -eq 0 ]; then
            send_alert "[ALERT] Sync Failed ${CONSECUTIVE_FAILURES} Times" "Service: OneDrive-GDrive Sync\nConsecutive failures: ${CONSECUTIVE_FAILURES}\nTime: ${TIMESTAMP}\n\nPlease check the service logs in Zeabur dashboard."
            ALERT_SENT=1
        fi
    fi

    rm -f "${SYNC_OUTPUT}"

    echo "Next sync in ${SYNC_INTERVAL} seconds..."
    sleep "${SYNC_INTERVAL}"
done
