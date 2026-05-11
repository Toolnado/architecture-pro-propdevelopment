#!/usr/bin/env bash
# simulate-incident.sh — Simulates suspicious Kubernetes security incidents for audit log analysis.
set -euo pipefail

kubectl create ns secure-ops 2>/dev/null || true
kubectl config set-context --current --namespace=secure-ops

kubectl create sa monitoring 2>/dev/null || true
kubectl run attacker-pod --image=alpine --command -- sleep 3600 2>/dev/null || true

echo "[1] Checking secret access permissions for monitoring SA..."
kubectl auth can-i get secrets --as=system:serviceaccount:secure-ops:monitoring || true

echo "[2] Attempting to access kube-system token as monitoring SA..."
SECRET=$(kubectl get secrets -n kube-system --as=system:serviceaccount:secure-ops:monitoring 2>/dev/null | grep 'default-token\|kubernetes.io/service-account' | head -n1 | awk '{print $1}' || true)
if [ -n "$SECRET" ]; then
  kubectl get secret -n kube-system "$SECRET" --as=system:serviceaccount:secure-ops:monitoring 2>/dev/null || true
fi

echo "[3] Creating privileged pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
  namespace: secure-ops
spec:
  containers:
  - name: pwn
    image: alpine
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF

echo "[4] Executing into coredns pod (kubectl exec in foreign pod)..."
COREDNS=$(kubectl get pods -n kube-system | grep coredns | awk '{print $1}' | head -n1)
if [ -n "$COREDNS" ]; then
  kubectl exec -n kube-system "$COREDNS" -- cat /etc/resolv.conf 2>/dev/null || true
fi

echo "[5] Creating unauthorized cluster-admin RoleBinding..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: escalate-binding
  namespace: secure-ops
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: secure-ops
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo "[6] Attempting to delete audit policy configmap..."
kubectl delete configmap audit-policy -n kube-system --as=admin 2>/dev/null || true

echo "Simulation complete."
