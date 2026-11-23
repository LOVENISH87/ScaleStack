#!/usr/bin/env bash
# ==============================================================================
# Script: backup_logs_to_s3.sh
# Purpose: Compresses Nginx access & error logs and uploads to AWS S3 bucket.
# ==============================================================================

set -euo pipefail

S3_BUCKET="${1:-${S3_BUCKET_NAME:-}}"
if [[ -z "$S3_BUCKET" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    S3_BUCKET="$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -raw s3_bucket_name 2>/dev/null || echo "")"
fi

if [[ -z "$S3_BUCKET" ]]; then
    echo "ERROR: S3_BUCKET is required. Usage: $0 <s3-bucket-name>" >&2
    exit 1
fi

LOG_DIR="${LOG_DIR:-/var/log/nginx}"
BACKUP_TMP_DIR="/tmp/log_backups"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
HOSTNAME="$(hostname -s 2>/dev/null || echo "app-server")"
ARCHIVE_NAME="${HOSTNAME}_logs_${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_TMP_DIR"
PAYLOAD_DIR="/tmp/payload_${TIMESTAMP}"
mkdir -p "$PAYLOAD_DIR"

if [[ -d "$LOG_DIR" ]]; then
    cp -r "$LOG_DIR"/* "$PAYLOAD_DIR/" 2>/dev/null || true
fi

# Also collect app logs or system activity if nginx logs are absent
if command -v journalctl &>/dev/null; then
    journalctl -u health-app -n 200 > "$PAYLOAD_DIR/health_app.log" 2>/dev/null || true
fi
if [[ ! -s "$PAYLOAD_DIR/health_app.log" ]]; then
    echo "=== ScaleStack Application Log Backup ===" > "$PAYLOAD_DIR/app.log"
    echo "Timestamp: $(date -u)" >> "$PAYLOAD_DIR/app.log"
    echo "Host: ${HOSTNAME}" >> "$PAYLOAD_DIR/app.log"
    echo "Cluster: Auto-Scaling Target Tracking Group" >> "$PAYLOAD_DIR/app.log"
fi

tar -czf "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}" -C "$PAYLOAD_DIR" .
rm -rf "$PAYLOAD_DIR"

echo "[$(date)] Uploading archive ${ARCHIVE_NAME} to s3://${S3_BUCKET}/logs/${HOSTNAME}/${ARCHIVE_NAME}..."
aws s3 cp "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}" "s3://${S3_BUCKET}/logs/${HOSTNAME}/${ARCHIVE_NAME}"
rm -f "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}"

echo "[$(date)] S3 log backup completed! Lambda will trigger and process the event."
