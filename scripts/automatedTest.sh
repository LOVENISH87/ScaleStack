#!/usr/bin/env bash
# ==============================================================================
# Script: automatedTest.sh
# Purpose: Verifies all endpoints, reverse proxy routing, and load balancing.
# ==============================================================================

set -uo pipefail

TARGET_HOST="${1:-localhost:8080}"
PASSED=0
FAILED=0

echo "=========================================================="
echo " Starting Automated Endpoint Test Suite against: ${TARGET_HOST}"
echo "=========================================================="

test_endpoint() {
    local endpoint="$1"
    local expected_code="$2"
    local description="$3"

    echo -n "Testing ${description} [${endpoint}]... "
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${TARGET_HOST}${endpoint}" 2>/dev/null || echo "000")

    if [[ "$code" == "$expected_code" ]]; then
        echo -e "\033[32m[PASS]\033[0m (HTTP ${code})"
        ((PASSED++))
    else
        echo -e "\033[31m[FAIL]\033[0m (Expected ${expected_code}, got ${code})"
        ((FAILED++))
    fi
}

# 1. Test Homepage Dashboard
test_endpoint "/" "200" "Homepage Dashboard"

# 2. Test Application Health check
test_endpoint "/health" "200" "Application Health Check"

# 3. Test Prometheus metrics endpoint
test_endpoint "/metrics" "200" "Prometheus Metrics Exporter"

# 4. Test 404 Error Handling
test_endpoint "/random-page-does-not-exist" "404" "404 Error Handling"

# 5. Test Load Balancing distribution (5 consecutive curls)
echo ""
echo "Testing Load Balancing Distribution across 5 requests:"
for i in {1..5}; do
    RAW_JSON=$(curl -s "http://${TARGET_HOST}/health" 2>/dev/null || echo "{}")
    HOSTNAME_VAL=$(python3 -c "import sys, json; print(json.loads('''$RAW_JSON''').get('hostname', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "  Request $i ➔ Served by: ${HOSTNAME_VAL}"
    sleep 0.2
done

echo ""
echo "=========================================================="
echo " Test Results: ${PASSED} Passed, ${FAILED} Failed"
echo "=========================================================="

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
