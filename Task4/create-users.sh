#!/usr/bin/env bash
# Script 1: Create Kubernetes users for PropDevelopment
# Uses certificate-based authentication with Minikube's CA.
# Each user's group (O field in certificate) determines their RBAC permissions.
# Run this script AFTER minikube start.

set -euo pipefail

CLUSTER_NAME="minikube"
WORK_DIR="./k8s-users"
MINIKUBE_CA_CRT="$HOME/.minikube/ca.crt"
MINIKUBE_CA_KEY="$HOME/.minikube/ca.key"
CERT_DAYS=365

mkdir -p "$WORK_DIR"

create_user() {
  local USERNAME=$1
  local GROUP=$2

  echo "[+] Creating user: $USERNAME (group: $GROUP)"

  openssl genrsa -out "$WORK_DIR/$USERNAME.key" 2048 2>/dev/null

  openssl req -new \
    -key "$WORK_DIR/$USERNAME.key" \
    -out "$WORK_DIR/$USERNAME.csr" \
    -subj "/CN=$USERNAME/O=$GROUP" 2>/dev/null

  openssl x509 -req \
    -in "$WORK_DIR/$USERNAME.csr" \
    -CA "$MINIKUBE_CA_CRT" \
    -CAkey "$MINIKUBE_CA_KEY" \
    -CAcreateserial \
    -out "$WORK_DIR/$USERNAME.crt" \
    -days "$CERT_DAYS" 2>/dev/null

  kubectl config set-credentials "$USERNAME" \
    --client-certificate="$(realpath "$WORK_DIR/$USERNAME.crt")" \
    --client-key="$(realpath "$WORK_DIR/$USERNAME.key")"

  kubectl config set-context "${USERNAME}-context" \
    --cluster="$CLUSTER_NAME" \
    --user="$USERNAME"

  echo "    Done: $WORK_DIR/$USERNAME.{key,crt}"
}

echo "=== PropDevelopment: Creating Kubernetes users ==="

# --- Privileged group: full cluster access, can view secrets ---
# Специалист по ИБ
create_user "ib-specialist"   "propdevelopment:privileged"
# DevOps-инженер
create_user "devops-engineer" "propdevelopment:privileged"

# --- Configurators group: can manage workloads, NO secrets ---
# Разработчики (по одному на домен — разграничение через RoleBinding в скрипте 3)
create_user "developer-sales" "propdevelopment:configurators"
create_user "developer-hcs"   "propdevelopment:configurators"

# --- Viewers group: read-only access to all namespaces, NO secrets ---
# Бизнес-аналитик
create_user "biz-analyst"    "propdevelopment:viewers"
# Менеджер
create_user "manager"        "propdevelopment:viewers"
# Владелец продукта
create_user "product-owner"  "propdevelopment:viewers"

# --- Finance group: read-only inside finance-domain namespace only ---
# Бухгалтер
create_user "accountant" "propdevelopment:finance"

echo ""
echo "=== All users created. Credentials stored in $WORK_DIR/ ==="
echo "Switch context example: kubectl config use-context devops-engineer-context"
