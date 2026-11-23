#!/usr/bin/env bash
# ==============================================================================
# Script: kind-smoke-test.sh
# Purpose: Prove the Kubernetes manifests work before spending money on EKS.
#          Creates a throwaway kind cluster, deploys the app image, installs
#          metrics-server, checks the endpoints, and then verifies the HPA
#          really scales out under /stress load.
#
# Usage: scripts/kind-smoke-test.sh
# Env:   CLUSTER (kind cluster name), IMAGE, NODE_PORT, KEEP=1 to keep cluster,
#        WITH_NAGIOS=1 to build/deploy the Nagios pod too (needs apt network)
# ==============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-scalestack-smoke}"
IMAGE="${IMAGE:-scalestack-web:dev}"
NODE_PORT="${NODE_PORT:-30080}"
KEEP="${KEEP:-0}"
WITH_NAGIOS="${WITH_NAGIOS:-0}"
NAGIOS_IMAGE="${NAGIOS_IMAGE:-scalestack-nagios:dev}"

PASSED=0
FAILED=0

pass() { echo "  [PASS] $*"; PASSED=$((PASSED + 1)); }
fail() { echo "  [FAIL] $*"; FAILED=$((FAILED + 1)); }

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but not installed." >&2
    exit 1
  }
}
need kind
need kubectl
need curl

# kind drives a container runtime. Docker is preferred; a stopped Docker
# Desktop engine is picked up from its user socket (no root needed), and
# rootless podman works only when cgroup delegation is configured.
RUNTIME=docker
if ! docker info >/dev/null 2>&1; then
  if [[ -S "${HOME}/.docker/desktop/docker.sock" ]] &&
    DOCKER_HOST="unix://${HOME}/.docker/desktop/docker.sock" docker info >/dev/null 2>&1; then
    export DOCKER_HOST="unix://${HOME}/.docker/desktop/docker.sock"
    echo "==> using Docker Desktop engine (${DOCKER_HOST})"
  elif podman info >/dev/null 2>&1; then
    export KIND_EXPERIMENTAL_PROVIDER=podman
    RUNTIME=podman
    echo "==> docker unavailable, falling back to rootless podman"
    echo "    (kind needs systemd Delegate=yes for the user session; see kind docs)"
  else
    echo "ERROR: no running docker or podman engine. Start one and retry." >&2
    exit 1
  fi
fi

cleanup() {
  if [[ "${KEEP}" == "1" ]]; then
    echo "==> KEEP=1: leaving kind cluster '${CLUSTER}' running"
    return
  fi
  echo "==> deleting kind cluster '${CLUSTER}'"
  kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> building image ${IMAGE} with ${RUNTIME}"
"${RUNTIME}" build -q -t "${IMAGE}" "${ROOT}/app" >/dev/null

if [[ "${WITH_NAGIOS}" == "1" ]]; then
  echo "==> building Nagios image ${NAGIOS_IMAGE}"
  "${RUNTIME}" build -q -t "${NAGIOS_IMAGE}" "${ROOT}/nagios" >/dev/null
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  echo "==> reusing kind cluster '${CLUSTER}'"
else
  echo "==> creating kind cluster '${CLUSTER}' (NodePort ${NODE_PORT} mapped to host)"
  kind create cluster --name "${CLUSTER}" --config "${ROOT}/scripts/kind-config.yaml"
fi

echo "==> loading image into kind"
kind load docker-image "${IMAGE}" --name "${CLUSTER}" >/dev/null
if [[ "${WITH_NAGIOS}" == "1" ]]; then
  kind load docker-image "${NAGIOS_IMAGE}" --name "${CLUSTER}" >/dev/null
fi

echo "==> applying k8s manifests"
kubectl apply -f "${ROOT}/k8s/00-namespace.yaml" >/dev/null
if [[ "${WITH_NAGIOS}" == "1" ]]; then
  # The Nagios pod reads the ALB DNS from a ConfigMap; in kind there is no ALB,
  # so it watches the in-cluster Service instead and the ALB check just fails.
  kubectl -n scalestack create configmap scalestack-nagios-config \
    --from-literal=alb_dns=scalestack-web.scalestack.svc.cluster.local \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n scalestack create secret generic scalestack-nagios-secret \
    --from-literal=admin_password=smoke-test-only \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi
for manifest in "${ROOT}"/k8s/*.yaml; do
  if [[ "$(basename "${manifest}")" == "50-nagios.yaml" && "${WITH_NAGIOS}" != "1" ]]; then
    continue
  fi
  kubectl apply -f "${manifest}" >/dev/null
done
kubectl -n scalestack set image deployment/scalestack-web "web=${IMAGE}" >/dev/null
kubectl -n scalestack rollout status deployment/scalestack-web --timeout=600s

if [[ "${WITH_NAGIOS}" == "1" ]]; then
  kubectl -n scalestack set image deployment/scalestack-nagios "nagios=${NAGIOS_IMAGE}" >/dev/null
  if kubectl -n scalestack rollout status deployment/scalestack-nagios --timeout=300s; then
    pass "Nagios pod started and /healthz is answering"
  else
    fail "Nagios pod did not become ready"
    kubectl -n scalestack logs deployment/scalestack-nagios --tail=50 || true
  fi
fi

echo "==> installing metrics-server (HPA data source)"
if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null
  # kind kubelets serve self-signed certificates
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
fi
kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s

echo "==> endpoints (http://localhost:${NODE_PORT})"
check_code() {
  local path="$1" want="$2" got
  got="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "http://localhost:${NODE_PORT}${path}" || echo 000)"
  if [[ "${got}" == "${want}" ]]; then
    pass "${path} -> ${got}"
  else
    fail "${path} -> ${got} (want ${want})"
  fi
}
check_code /health 200
check_code /stats 200
check_code / 200
check_code /does-not-exist 404

echo "==> waiting for HPA metrics"
HPA_READY=0
for _ in $(seq 1 60); do
  current="$(kubectl -n scalestack get hpa scalestack-web \
    -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
  if [[ -n "${current}" ]]; then
    HPA_READY=1
    pass "HPA reports CPU utilisation (${current}%)"
    break
  fi
  sleep 3
done
[[ "${HPA_READY}" == "1" ]] || fail "HPA never reported CPU metrics"

echo "==> stress test: POST /stress in every pod, expect scale-up above 2"
for pod in $(kubectl -n scalestack get pods -o name); do
  kubectl -n scalestack exec "${pod}" -- python3 -c \
    "import urllib.request as u; print(u.urlopen(u.Request('http://127.0.0.1:8080/stress', method='POST'), timeout=5).read().decode())" \
    >/dev/null 2>&1 || true
done

SCALED=0
for _ in $(seq 1 60); do
  desired="$(kubectl -n scalestack get hpa scalestack-web -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo 0)"
  if [[ "${desired}" -gt 2 ]]; then
    SCALED=1
    pass "HPA scaled desiredReplicas to ${desired}"
    break
  fi
  sleep 3
done
[[ "${SCALED}" == "1" ]] || fail "HPA never scaled above 2 replicas"

echo "==> final state"
kubectl -n scalestack get deploy,hpa,pods,svc

echo
echo "=========================================================="
echo " Smoke results: ${PASSED} passed, ${FAILED} failed"
echo "=========================================================="
[[ "${FAILED}" -eq 0 ]]
