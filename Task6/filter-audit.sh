#!/usr/bin/env bash
# filter-audit.sh — Filter Kubernetes audit.log for suspicious events.
# Usage: ./filter-audit.sh [path/to/audit.log]
# Default log path: /var/log/audit.log

set -euo pipefail

LOG_FILE="${1:-/var/log/audit.log}"
OUTPUT_DIR="./audit-results"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: audit log not found at $LOG_FILE" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with: apt install jq / brew install jq" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "=== PropDevelopment: Kubernetes Audit Log Analysis ==="
echo "Log: $LOG_FILE"
echo "Output: $OUTPUT_DIR/"
echo ""

# ---------------------------------------------------------------
# 1. Secret access — any verb on secrets resource
# ---------------------------------------------------------------
echo "[1] Checking secret access events..."
jq -c 'select(.objectRef.resource == "secrets" and
        (.verb == "get" or .verb == "list" or .verb == "watch" or .verb == "create"))' \
  "$LOG_FILE" > "$OUTPUT_DIR/secrets-access.json"
COUNT=$(wc -l < "$OUTPUT_DIR/secrets-access.json")
echo "    Found: $COUNT event(s) → $OUTPUT_DIR/secrets-access.json"

# ---------------------------------------------------------------
# 2. kubectl exec into pods (any namespace)
# ---------------------------------------------------------------
echo "[2] Checking kubectl exec events..."
jq -c 'select((.verb == "create" or .verb == "get") and .objectRef.subresource == "exec")' \
  "$LOG_FILE" > "$OUTPUT_DIR/exec-events.json"
COUNT=$(wc -l < "$OUTPUT_DIR/exec-events.json")
echo "    Found: $COUNT event(s) → $OUTPUT_DIR/exec-events.json"

# ---------------------------------------------------------------
# 3. Privileged pod creation
# ---------------------------------------------------------------
echo "[3] Checking privileged pod creation..."
jq -c 'select(.objectRef.resource == "pods" and
        .verb == "create" and
        (.requestObject.spec.containers[]?.securityContext.privileged == true) // false)' \
  "$LOG_FILE" > "$OUTPUT_DIR/privileged-pods.json"
COUNT=$(wc -l < "$OUTPUT_DIR/privileged-pods.json")
echo "    Found: $COUNT event(s) → $OUTPUT_DIR/privileged-pods.json"

# ---------------------------------------------------------------
# 4. Audit policy deletion or modification
# ---------------------------------------------------------------
echo "[4] Checking audit-policy modifications..."
grep -i 'audit-policy' "$LOG_FILE" > "$OUTPUT_DIR/audit-policy-changes.log" || true
COUNT=$(wc -l < "$OUTPUT_DIR/audit-policy-changes.log")
echo "    Found: $COUNT line(s) → $OUTPUT_DIR/audit-policy-changes.log"

# ---------------------------------------------------------------
# 5. RoleBinding / ClusterRoleBinding creation — privilege escalation
# ---------------------------------------------------------------
echo "[5] Checking RoleBinding creation events..."
jq -c 'select((.objectRef.resource == "rolebindings" or
               .objectRef.resource == "clusterrolebindings") and
        .verb == "create")' \
  "$LOG_FILE" > "$OUTPUT_DIR/rolebinding-creation.json"
COUNT=$(wc -l < "$OUTPUT_DIR/rolebinding-creation.json")
echo "    Found: $COUNT event(s) → $OUTPUT_DIR/rolebinding-creation.json"

# ---------------------------------------------------------------
# 6. Cross-namespace secret access by service accounts
#    (SA from namespace X accessing secrets in namespace Y)
# ---------------------------------------------------------------
echo "[6] Checking cross-namespace secret access by service accounts..."
jq -c 'select(.objectRef.resource == "secrets" and
        (.user.username | startswith("system:serviceaccount:")) and
        (.user.username | split(":")[2]) != .objectRef.namespace)' \
  "$LOG_FILE" > "$OUTPUT_DIR/cross-namespace-secrets.json"
COUNT=$(wc -l < "$OUTPUT_DIR/cross-namespace-secrets.json")
echo "    Found: $COUNT event(s) → $OUTPUT_DIR/cross-namespace-secrets.json"

# ---------------------------------------------------------------
# 7. Actions inside kube-system by non-system users
# ---------------------------------------------------------------
echo "[7] Checking actions in kube-system by non-system users..."
jq -c 'select(.objectRef.namespace == "kube-system" and
        (.user.username | startswith("system:") | not) and
        (.verb == "create" or .verb == "delete" or .verb == "update" or .verb == "patch"))' \
  "$LOG_FILE" > "$OUTPUT_DIR/kube-system-mutations.json"
COUNT=$(wc -l < "$OUTPUT_DIR/kube-system-mutations.json")
echo "    Found: $COUNT event(s) → $OUTPUT_DIR/kube-system-mutations.json"

# ---------------------------------------------------------------
# 8. Combined suspicious events summary (all checks merged)
# ---------------------------------------------------------------
echo "[8] Building combined suspicious events summary..."
jq -c '
  select(
    (.objectRef.resource == "secrets" and (.verb == "get" or .verb == "list")) or
    ((.verb == "create" or .verb == "get") and .objectRef.subresource == "exec") or
    (.objectRef.resource == "pods" and .verb == "create" and
      ((.requestObject.spec.containers[]?.securityContext.privileged == true) // false)) or
    ((.objectRef.resource == "rolebindings" or .objectRef.resource == "clusterrolebindings") and
      .verb == "create") or
    (.objectRef.namespace == "kube-system" and
      (.user.username | startswith("system:") | not) and
      (.verb == "delete" or .verb == "create"))
  )' \
  "$LOG_FILE" > "$OUTPUT_DIR/suspicious-combined.json"
COUNT=$(wc -l < "$OUTPUT_DIR/suspicious-combined.json")
echo "    Found: $COUNT suspicious event(s) → $OUTPUT_DIR/suspicious-combined.json"

echo ""
echo "=== Analysis complete. Results in $OUTPUT_DIR/ ==="
echo ""
echo "Quick summary:"
echo "  secrets-access.json          — secret read events"
echo "  exec-events.json             — kubectl exec events"
echo "  privileged-pods.json         — privileged container creation"
echo "  audit-policy-changes.log     — audit policy deletions/modifications"
echo "  rolebinding-creation.json    — role binding creation (privilege escalation)"
echo "  cross-namespace-secrets.json — SA accessing secrets in foreign namespaces"
echo "  kube-system-mutations.json   — mutations in kube-system by non-system users"
echo "  suspicious-combined.json     — all suspicious events merged"
