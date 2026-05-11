#!/usr/bin/env bash
# Script 2: Create Kubernetes namespaces and RBAC roles for PropDevelopment
# Run this script as cluster-admin (default minikube context).

set -euo pipefail

echo "=== PropDevelopment: Creating namespaces and RBAC roles ==="

# ---------------------------------------------------------------
# Namespaces — one per business domain
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: sales-domain
  labels:
    domain: sales
---
apiVersion: v1
kind: Namespace
metadata:
  name: hcs-domain
  labels:
    domain: hcs
---
apiVersion: v1
kind: Namespace
metadata:
  name: finance-domain
  labels:
    domain: finance
---
apiVersion: v1
kind: Namespace
metadata:
  name: data-domain
  labels:
    domain: data
EOF
echo "[+] Namespaces created: sales-domain, hcs-domain, finance-domain, data-domain"

# ---------------------------------------------------------------
# ClusterRole: privileged
# Full access to all resources, including secrets.
# For: Специалист по ИБ, DevOps-инженер
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: propdevelopment:privileged
  labels:
    propdevelopment/tier: privileged
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
EOF
echo "[+] ClusterRole created: propdevelopment:privileged"

# ---------------------------------------------------------------
# ClusterRole: viewer
# Read-only access to all namespaces. Secrets are excluded.
# For: Бизнес-аналитик, Менеджер, Владелец продукта
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: propdevelopment:viewer
  labels:
    propdevelopment/tier: viewer
rules:
- apiGroups: [""]
  resources:
    - pods
    - pods/log
    - services
    - endpoints
    - configmaps
    - namespaces
    - nodes
    - persistentvolumeclaims
    - serviceaccounts
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources:
    - deployments
    - replicasets
    - daemonsets
    - statefulsets
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources:
    - ingresses
    - networkpolicies
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources:
    - jobs
    - cronjobs
  verbs: ["get", "list", "watch"]
EOF
echo "[+] ClusterRole created: propdevelopment:viewer"

# ---------------------------------------------------------------
# ClusterRole: configurator
# Full management of workloads and config. Secrets are excluded.
# Applied via RoleBinding (namespace-scoped) in script 3.
# For: Разработчики (привязываются к конкретному namespace)
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: propdevelopment:configurator
  labels:
    propdevelopment/tier: configurator
rules:
- apiGroups: [""]
  resources:
    - pods
    - pods/log
    - pods/exec
    - pods/portforward
    - services
    - endpoints
    - configmaps
    - persistentvolumeclaims
    - serviceaccounts
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources:
    - deployments
    - deployments/scale
    - replicasets
    - daemonsets
    - statefulsets
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources:
    - ingresses
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["batch"]
  resources:
    - jobs
    - cronjobs
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
echo "[+] ClusterRole created: propdevelopment:configurator"

# ---------------------------------------------------------------
# Role: finance-viewer (namespace-scoped, finance-domain only)
# Read-only access limited to the finance namespace.
# For: Бухгалтер
# ---------------------------------------------------------------
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: propdevelopment:finance-viewer
  namespace: finance-domain
  labels:
    propdevelopment/tier: finance
rules:
- apiGroups: [""]
  resources:
    - pods
    - pods/log
    - services
    - endpoints
    - configmaps
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources:
    - deployments
  verbs: ["get", "list", "watch"]
EOF
echo "[+] Role created: propdevelopment:finance-viewer (namespace: finance-domain)"

echo ""
echo "=== All RBAC roles created successfully ==="
