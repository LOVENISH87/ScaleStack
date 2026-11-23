#!/usr/bin/env bash
# ==============================================================================
# Script: k8s-bootstrap.sh
# Purpose: Point kubectl at the Terraform EKS cluster, deploy ScaleStack and the
#          Nagios pod, and install metrics-server so the 40% CPU HPA has data.
#
# Usage:
#   IMAGE_URI=<ecr-url>:<tag> \
#   NAGIOS_IMAGE_URI=<ecr-url>:nagios \
#   NAGIOS_ADMIN_PASSWORD='<strong-password>' \
#     scripts/k8s-bootstrap.sh
#
# Env:
#   CLUSTER_NAME         EKS cluster name    (default: terraform output)
#   AWS_REGION           region              (default: terraform output / env)
#   IMAGE_URI            app image           (default: <ecr repo>:latest)
#   NAGIOS_IMAGE_URI     nagios image        (default: <same repo>:nagios)
#   NAGIOS_ADMIN_PASSWORD  digest login password for nagiosadmin (required
#                          unless SKIP_NAGIOS=1; never written to the repo)
#   SKIP_NAGIOS=1        deploy the app only
#   SKIP_METRICS=1       metrics-server already installed
# ==============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
K8S_DIR="${ROOT}/k8s"

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
NAGIOS_IMAGE_URI="${NAGIOS_IMAGE_URI:-${IMAGE_URI%:*}:nagios}"
ALB_DNS="${ALB_DNS:-$(tf_output alb_dns_name)}"

if [[ "${SKIP_NAGIOS:-0}" != "1" ]]; then
  if [[ -z "${ALB_DNS}" ]]; then
    echo "ERROR: no ALB DNS name from Terraform; Nagios needs it for its checks." >&2
    exit 1
  fi
  if [[ -z "${NAGIOS_ADMIN_PASSWORD:-}" ]]; then
    echo "ERROR: set NAGIOS_ADMIN_PASSWORD='<at least 8 chars>' (or SKIP_NAGIOS=1)." >&2
    exit 1
  fi
fi

echo "==> kubectl -> cluster ${CLUSTER_NAME} (${AWS_REGION})"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

echo "==> creating the namespace"
kubectl apply -f "${K8S_DIR}/00-namespace.yaml"

if [[ "${SKIP_NAGIOS:-0}" != "1" ]]; then
  # These must exist before the Deployment is created, or the Nagios pod sits in
  # CreateContainerConfigError until they appear.
  echo "==> creating the Nagios ConfigMap and Secret"
  kubectl -n scalestack create configmap scalestack-nagios-config \
    --from-literal=alb_dns="${ALB_DNS}" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n scalestack create secret generic scalestack-nagios-secret \
    --from-literal=admin_password="${NAGIOS_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "==> applying manifests from k8s/"
for manifest in "${K8S_DIR}"/*.yaml; do
  if [[ "$(basename "${manifest}")" == "50-nagios.yaml" && "${SKIP_NAGIOS:-0}" == "1" ]]; then
    echo "    skipping $(basename "${manifest}") (SKIP_NAGIOS=1)"
    continue
  fi
  kubectl apply -f "${manifest}"
done

echo "==> deploying image ${IMAGE_URI}"
kubectl -n scalestack set image deployment/scalestack-web "web=${IMAGE_URI}"
kubectl -n scalestack rollout status deployment/scalestack-web --timeout=300s

if [[ "${SKIP_NAGIOS:-0}" != "1" ]]; then
  echo "==> deploying image ${NAGIOS_IMAGE_URI}"
  kubectl -n scalestack set image deployment/scalestack-nagios "nagios=${NAGIOS_IMAGE_URI}"
  kubectl -n scalestack rollout status deployment/scalestack-nagios --timeout=300s
fi

if [[ "${SKIP_METRICS:-0}" != "1" ]]; then
  # EKS does not ship metrics-server, and without it the HPA stays at
  # "<unknown>/40%" and never scales.
  if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
    echo "==> installing metrics-server"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  fi
  kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s
fi

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
echo "App URL : http://${ALB_DNS}/"
if [[ "${SKIP_NAGIOS:-0}" != "1" ]]; then
  echo "Nagios  : http://${ALB_DNS}/nagios/  (nagiosadmin + NAGIOS_ADMIN_PASSWORD)"
fi
echo "HPA     : kubectl -n scalestack get hpa -w"
echo "Stress  : curl -X POST http://${ALB_DNS}/stress"
