#!/usr/bin/env bash
# ==============================================================================
# Script: k8s-bootstrap.sh
# Purpose: Point kubectl at the Terraform EKS cluster, deploy ScaleStack, and
#          install metrics-server so the 40% CPU HPA actually has data.
#
# Usage:
#   IMAGE_URI=<ecr-url>:<tag> scripts/k8s-bootstrap.sh
#
# Env:
#   CLUSTER_NAME  EKS cluster name      (default: terraform output)
#   AWS_REGION    region                (default: terraform output / AWS_REGION)
#   IMAGE_URI     image to deploy       (default: <ecr repo>:latest)
#   SKIP_METRICS  set to 1 if metrics-server is already installed
# ==============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but not installed." >&2
    exit 1
  }
}
need aws
need kubectl

tf_output() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

AWS_REGION="${AWS_REGION:-$(tf_output aws_region)}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-$(tf_output cluster_name)}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "ERROR: no cluster name. Apply Terraform first or set CLUSTER_NAME." >&2
  exit 1
fi

IMAGE_URI="${IMAGE_URI:-$(tf_output ecr_repository_url):latest}"

echo "==> kubectl -> cluster ${CLUSTER_NAME} (${AWS_REGION})"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

echo "==> applying manifests from k8s/"
kubectl apply -f "${ROOT}/k8s/"

echo "==> deploying image ${IMAGE_URI}"
kubectl -n scalestack set image deployment/scalestack-web "web=${IMAGE_URI}"

if [[ "${SKIP_METRICS:-0}" != "1" ]]; then
  # EKS does not ship metrics-server, and without it the HPA stays at
  # "<unknown>/40%" and never scales.
  if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
    echo "==> installing metrics-server"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  fi
  kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s
fi

echo "==> waiting for rollout"
kubectl -n scalestack rollout status deployment/scalestack-web --timeout=300s

echo "==> waiting for the HPA to report CPU metrics"
for _ in $(seq 1 40); do
  current="$(kubectl -n scalestack get hpa scalestack-web \
    -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
  [[ -n "${current}" ]] && break
  sleep 5
done

echo
kubectl -n scalestack get deploy,hpa,pods,svc -o wide

echo
echo "App URL : http://$(tf_output alb_dns_name)/"
echo "HPA     : kubectl -n scalestack get hpa -w"
echo "Stress  : curl -X POST http://<alb>/stress"
