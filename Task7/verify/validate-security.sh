#!/usr/bin/env bash
# validate-security.sh — Validates that PodSecurity labels and Gatekeeper constraints are active.
# Usage: ./validate-security.sh
# Run from Task7/ directory.

set -uo pipefail

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }

echo "=== Security Configuration Validation ==="
echo ""

# --- 1. PodSecurity Admission ---
echo "--- PodSecurity Admission ---"

ENFORCE=$(kubectl get namespace audit-zone -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
if [ "$ENFORCE" = "restricted" ]; then
  pass "audit-zone enforce=restricted"
else
  fail "audit-zone enforce label missing or not 'restricted' (got: '${ENFORCE}')"
fi

AUDIT=$(kubectl get namespace audit-zone -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/audit}' 2>/dev/null || echo "")
[ "$AUDIT" = "restricted" ] && pass "audit-zone audit=restricted" || warn "audit-zone audit label: '${AUDIT}'"

WARN_LABEL=$(kubectl get namespace audit-zone -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/warn}' 2>/dev/null || echo "")
[ "$WARN_LABEL" = "restricted" ] && pass "audit-zone warn=restricted" || warn "audit-zone warn label: '${WARN_LABEL}'"

echo ""
echo "--- OPA Gatekeeper ---"

# Check if Gatekeeper is installed
if kubectl get deployment gatekeeper-controller-manager -n gatekeeper-system >/dev/null 2>&1; then
  READY=$(kubectl get deployment gatekeeper-controller-manager -n gatekeeper-system \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  [ "${READY:-0}" -gt 0 ] && pass "Gatekeeper controller running ($READY replicas)" || fail "Gatekeeper controller not ready"

  # Check constraint templates
  for TMPL in k8spspprivilegedcontainer k8spspvolumetypes k8spspallowedusers; do
    if kubectl get constrainttemplate "$TMPL" >/dev/null 2>&1; then
      pass "ConstraintTemplate $TMPL exists"
    else
      fail "ConstraintTemplate $TMPL not found"
    fi
  done

  # Check constraints
  for CONSTRAINT in psp-deny-privileged psp-deny-hostpath psp-require-nonroot; do
    FOUND=false
    for KIND in K8sPSPPrivilegedContainer K8sPSPVolumeTypes K8sPSPAllowedUsers; do
      if kubectl get "$KIND" "$CONSTRAINT" >/dev/null 2>&1; then
        FOUND=true
        VIOLATIONS=$(kubectl get "$KIND" "$CONSTRAINT" -o jsonpath='{.status.totalViolations}' 2>/dev/null || echo "?")
        pass "Constraint $CONSTRAINT active (violations: $VIOLATIONS)"
        break
      fi
    done
    $FOUND || fail "Constraint $CONSTRAINT not found"
  done
else
  warn "OPA Gatekeeper not installed — skipping Gatekeeper checks"
  warn "To install: kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.18.0/deploy/gatekeeper.yaml"
fi

echo ""
echo "--- Running pods in audit-zone ---"
kubectl get pods -n audit-zone 2>/dev/null || warn "No pods in audit-zone"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
