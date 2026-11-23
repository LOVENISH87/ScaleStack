#!/usr/bin/env bash
# ==============================================================================
# Archive the ScaleStack pods' container logs from the node's /var/log/pods and
# upload one tarball per run to S3, where the bucket notification invokes the
# log-processor Lambda (filter: prefix logs/, suffix .tar.gz).
#
# Credentials come from the node's IAM role via IMDS: the EKS node role already
# has s3:PutObject/GetObject/ListBucket on this bucket, and the launch template
# sets http_put_response_hop_limit = 2 so pods can reach the metadata service.
# No static keys anywhere.
#
# Env:
#   S3_BUCKET             required (from the scalestack-log-config ConfigMap)
#   NODE_NAME             node the pod runs on (Downward API)
#   LOG_WINDOW_MINUTES    only logs touched in this window (default 60)
#   POD_LOG_DIR           log root (default /var/log/pods)
#   DRY_RUN=1             build the archive, print the key, skip the upload
# ==============================================================================

set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET must be set}"

# Fail loudly if the image is missing a tool: an earlier version silently
# produced an empty archive because `find` was absent and its error was hidden.
for tool in find tar gzip aws; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: required tool '${tool}' is not installed in this image." >&2
    exit 1
  }

done

POD_LOG_DIR="${POD_LOG_DIR:-/var/log/pods}"
NODE_NAME="${NODE_NAME:-$(uname -n)}"
LOG_WINDOW_MINUTES="${LOG_WINDOW_MINUTES:-60}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
KEY="logs/${NODE_NAME}/${TIMESTAMP}.tar.gz"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
archive="${work_dir}/${TIMESTAMP}.tar.gz"

if [[ ! -d "${POD_LOG_DIR}" ]]; then
  echo "ERROR: ${POD_LOG_DIR} does not exist; nothing to archive." >&2
  exit 1
fi

# Container logs live at <dir>/<ns>_<pod>_<uid>/<container>/<n>.log. Only this
# project's pods, and only files written inside the window.
mapfile -t files < <(
  find "${POD_LOG_DIR}" \
    -type f \
    -name '*.log' \
    -mmin "-${LOG_WINDOW_MINUTES}" \
    -path "*/scalestack_*/*" \
    -print | sort
)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No ScaleStack pod logs changed in the last ${LOG_WINDOW_MINUTES} minutes; nothing to upload."
  exit 0
fi

relative=()
for file in "${files[@]}"; do
  relative+=("${file#"${POD_LOG_DIR}"/}")
done

tar -czf "${archive}" -C "${POD_LOG_DIR}" "${relative[@]}"
size="$(du -h "${archive}" | cut -f1)"
echo "Archived ${#files[@]} log file(s) (${size}) from ${NODE_NAME}."

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN=1: would upload to s3://${S3_BUCKET}/${KEY}"
  tar -tzf "${archive}" | head -20
  exit 0
fi

aws s3 cp "${archive}" "s3://${S3_BUCKET}/${KEY}" --only-show-errors
echo "Uploaded s3://${S3_BUCKET}/${KEY}; the Lambda trigger will process it."
