#!/usr/bin/env bash
# ==============================================================================
# Script: backup_logs_to_s3.sh
# Purpose: Compresses Nginx access & error logs and uploads to AWS S3 bucket.
# ==============================================================================

set -euo pipefail

S3_BUCKET="${1:-${S3_BUCKET_NAME:-}}"
LOG_DIR="${LOG_DIR:-/var/log/nginx}"
BACKUP_TMP_DIR="/tmp/log_backups"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
HOSTNAME="$(hostname -s)"
ARCHIVE_NAME="${HOSTNAME}_nginx_logs_${TIMESTAMP}.tar.gz"

if [[ -z "$S3_BUCKET" ]]; then
    echo "ERROR: S3_BUCKET is required. Usage: $0 <s3-bucket-name>" >&2
    exit 1
fi

mkdir -p "$BACKUP_TMP_DIR"

echo "[$(date)] Starting Nginx log backup on ${HOSTNAME}..."

if [[ -d "$LOG_DIR" ]]; then
    tar -czf "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}" -C "$LOG_DIR" .
    echo "[$(date)] Created archive: ${ARCHIVE_NAME} ($(du -h "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}" | cut -f1))"

    echo "[$(date)] Uploading to s3://${S3_BUCKET}/logs/${HOSTNAME}/${ARCHIVE_NAME}..."
    aws s3 cp "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}" "s3://${S3_BUCKET}/logs/${HOSTNAME}/${ARCHIVE_NAME}"

    rm -f "${BACKUP_TMP_DIR}/${ARCHIVE_NAME}"
    echo "[$(date)] Backup completed successfully!"
else
    echo "WARNING: Log directory ${LOG_DIR} does not exist. Nothing to back up."
fi
