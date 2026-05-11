#!/usr/bin/env bash
# Script 3: Bind users and groups to RBAC roles for PropDevelopment
# Run AFTER create-roles.sh and create-users.sh.
# Run as cluster-admin (default minikube context).

set -euo pipefail

echo "=== PropDevelopment: Creating RBAC role bindings ==="

# ---------------------------------------------------------------
# ClusterRoleBinding: privileged group → propdevelopment:privileged
# Grants full cluster access (including secrets) cluster-wide.
# Members: Специалист по ИБ (ib-specialist), DevOps-инженер (devops-engineer)
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: propdevelopment:privileged-binding
subjects:
- kind: Group
  name: propdevelopment:privileged
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdevelopment:privileged
  apiGroup: rbac.authorization.k8s.io
EOF
echo "[+] ClusterRoleBinding: propdevelopment:privileged → propdevelopment:privileged"

# ---------------------------------------------------------------
# ClusterRoleBinding: viewers group → propdevelopment:viewer
# Grants read-only access cluster-wide. No access to secrets.
# Members: biz-analyst, product-owner, manager
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: propdevelopment:viewer-binding
subjects:
- kind: Group
  name: propdevelopment:viewers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdevelopment:viewer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "[+] ClusterRoleBinding: propdevelopment:viewers → propdevelopment:viewer"

# ---------------------------------------------------------------
# RoleBinding: developer-sales → propdevelopment:configurator (sales-domain)
# Разработчик домена продаж управляет только своим namespace.
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: propdevelopment:configurator-sales
  namespace: sales-domain
subjects:
- kind: User
  name: developer-sales
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdevelopment:configurator
  apiGroup: rbac.authorization.k8s.io
EOF
echo "[+] RoleBinding: developer-sales → propdevelopment:configurator (sales-domain)"

# ---------------------------------------------------------------
# RoleBinding: developer-hcs → propdevelopment:configurator (hcs-domain)
# Разработчик домена ЖКУ управляет только своим namespace.
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: propdevelopment:configurator-hcs
  namespace: hcs-domain
subjects:
- kind: User
  name: developer-hcs
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: propdevelopment:configurator
  apiGroup: rbac.authorization.k8s.io
EOF
echo "[+] RoleBinding: developer-hcs → propdevelopment:configurator (hcs-domain)"

# ---------------------------------------------------------------
# RoleBinding: finance group → propdevelopment:finance-viewer (finance-domain)
# Бухгалтер имеет read-only доступ только к финансовому namespace.
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: propdevelopment:finance-viewer-binding
  namespace: finance-domain
subjects:
- kind: User
  name: accountant
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: propdevelopment:finance
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: propdevelopment:finance-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "[+] RoleBinding: propdevelopment:finance → propdevelopment:finance-viewer (finance-domain)"

echo ""
echo "=== All role bindings created successfully ==="
echo ""
echo "Verify bindings:"
echo "  kubectl get clusterrolebindings | grep propdevelopment"
echo "  kubectl get rolebindings -A | grep propdevelopment"
echo ""
echo "Test access (example):"
echo "  kubectl auth can-i list secrets --as=ib-specialist                     # yes"
echo "  kubectl auth can-i list secrets --as=biz-analyst                       # no"
echo "  kubectl auth can-i create deployments --as=developer-sales -n sales-domain  # yes"
echo "  kubectl auth can-i create deployments --as=developer-sales -n hcs-domain    # no"
echo "  kubectl auth can-i list pods --as=accountant -n finance-domain         # yes"
echo "  kubectl auth can-i list pods --as=accountant -n sales-domain           # no"
