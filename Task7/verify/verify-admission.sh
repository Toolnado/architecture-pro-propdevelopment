#!/usr/bin/env bash
# verify-admission.sh — Verifies that PodSecurity Admission blocks insecure pods
# and allows secure pods in the audit-zone namespace.
# Usage: ./verify-admission.sh
# Run from Task7/ directory.

set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$(dirname "$SCRIPT_DIR")"

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== PodSecurity Admission Verification ==="
echo ""

# Ensure namespace exists
kubectl apply -f "$TASK_DIR/01-create-namespace.yaml" >/dev/null 2>&1

echo "--- Insecure manifests: expecting REJECTION ---"

# 1. Privileged pod
echo "[1] Privileged pod (01-privileged-pod.yaml)..."
OUT=$(kubectl apply -f "$TASK_DIR/insecure-manifests/01-privileged-pod.yaml" 2>&1 || true)
if echo "$OUT" | grep -qiE "denied|forbidden|violat|Error"; then
  pass "privileged pod was rejected: $(echo "$OUT" | grep -oiE 'violat[^\.]+|denied[^\n]+'| head -1)"
else
  fail "privileged pod was NOT rejected. Output: $OUT"
fi

# 2. HostPath pod
echo "[2] HostPath pod (02-hostpath-pod.yaml)..."
OUT=$(kubectl apply -f "$TASK_DIR/insecure-manifests/02-hostpath-pod.yaml" 2>&1 || true)
if echo "$OUT" | grep -qiE "denied|forbidden|violat|Error"; then
  pass "hostPath pod was rejected"
else
  fail "hostPath pod was NOT rejected. Output: $OUT"
fi

# 3. Root user pod
echo "[3] Root-user pod (03-root-user-pod.yaml)..."
OUT=$(kubectl apply -f "$TASK_DIR/insecure-manifests/03-root-user-pod.yaml" 2>&1 || true)
if echo "$OUT" | grep -qiE "denied|forbidden|violat|Error"; then
  pass "root-user pod was rejected"
else
  fail "root-user pod was NOT rejected. Output: $OUT"
fi

echo ""
echo "--- Secure manifests: expecting ACCEPTANCE ---"

# 4. Secure pod 1
echo "[4] Secure pod 1 (01-secure.yaml)..."
kubectl delete pod pod-secure-1 -n audit-zone --ignore-not-found >/dev/null 2>&1
OUT=$(kubectl apply -f "$TASK_DIR/secure-manifests/01-secure.yaml" 2>&1)
if echo "$OUT" | grep -qiE "created|configured"; then
  pass "secure pod 1 was accepted"
  kubectl delete pod pod-secure-1 -n audit-zone --ignore-not-found >/dev/null 2>&1
else
  fail "secure pod 1 was rejected. Output: $OUT"
fi

# 5. Secure pod 2
echo "[5] Secure pod 2 (02-secure.yaml)..."
kubectl delete pod pod-secure-2 -n audit-zone --ignore-not-found >/dev/null 2>&1
OUT=$(kubectl apply -f "$TASK_DIR/secure-manifests/02-secure.yaml" 2>&1)
if echo "$OUT" | grep -qiE "created|configured"; then
  pass "secure pod 2 was accepted"
  kubectl delete pod pod-secure-2 -n audit-zone --ignore-not-found >/dev/null 2>&1
else
  fail "secure pod 2 was rejected. Output: $OUT"
fi

# 6. Secure pod 3
echo "[6] Secure pod 3 (03-secure.yaml)..."
kubectl delete pod pod-secure-3 -n audit-zone --ignore-not-found >/dev/null 2>&1
OUT=$(kubectl apply -f "$TASK_DIR/secure-manifests/03-secure.yaml" 2>&1)
if echo "$OUT" | grep -qiE "created|configured"; then
  pass "secure pod 3 was accepted"
  kubectl delete pod pod-secure-3 -n audit-zone --ignore-not-found >/dev/null 2>&1
else
  fail "secure pod 3 was rejected. Output: $OUT"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
