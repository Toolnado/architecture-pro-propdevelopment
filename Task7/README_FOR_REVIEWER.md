# Task 7: Pod Security — README для ревьюера

## Что реализовано

### 1. Namespace с PodSecurity Admission (`01-create-namespace.yaml`)
Namespace `audit-zone` создан с тремя уровнями политики `restricted`:
- `enforce` — блокирует несоответствующие поды при создании
- `audit` — записывает в audit log нарушения (без блокировки)
- `warn` — возвращает предупреждение клиенту

```bash
kubectl apply -f 01-create-namespace.yaml
```

### 2. Небезопасные манифесты (`insecure-manifests/`)

| Файл | Нарушение | Ожидаемый результат |
|---|---|---|
| `01-privileged-pod.yaml` | `privileged: true` | Отклонён PodSecurity + Gatekeeper |
| `02-hostpath-pod.yaml` | `hostPath` volume | Отклонён PodSecurity + Gatekeeper |
| `03-root-user-pod.yaml` | `runAsUser: 0` | Отклонён PodSecurity + Gatekeeper |

Применение — для проверки отклонения:
```bash
kubectl apply -f insecure-manifests/  # все три должны быть отклонены
```

### 3. Безопасные манифесты (`secure-manifests/`)

Все три пода используют образ `busybox:1.36` с командой `sleep 3600`.  
Каждый соответствует профилю `restricted`:

| Параметр | Значение |
|---|---|
| `privileged` | `false` |
| `runAsNonRoot` | `true` |
| `runAsUser` | `1000` |
| `readOnlyRootFilesystem` | `true` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |
| `seccompProfile.type` | `RuntimeDefault` |

```bash
kubectl apply -f secure-manifests/  # все три должны быть приняты
```

### 4. OPA Gatekeeper (`gatekeeper/`)

#### Установка Gatekeeper
```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.18.0/deploy/gatekeeper.yaml
kubectl wait --for=condition=Ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=120s
```

#### Применение политик
```bash
# Сначала ConstraintTemplates (определения типов)
kubectl apply -f gatekeeper/constraint-templates/

# Затем Constraints (экземпляры правил)
kubectl apply -f gatekeeper/constraints/
```

#### Правила Gatekeeper

| ConstraintTemplate | Constraint | Запрещает |
|---|---|---|
| `K8sPSPPrivilegedContainer` | `psp-deny-privileged` | `privileged: true` |
| `K8sPSPVolumeTypes` | `psp-deny-hostpath` | `hostPath` volumes |
| `K8sPSPAllowedUsers` | `psp-require-nonroot` | root UID, отсутствие `runAsNonRoot`, отсутствие `readOnlyRootFilesystem` |

### 5. Политика аудита (`audit-policy.yaml`)

Фиксирует все операции создания/изменения/удаления подов, Gatekeeper-ресурсов и RBAC.

## Как проверить

### Шаг 1 — Запустить скрипт проверки PodSecurity Admission
```bash
chmod +x verify/verify-admission.sh
cd Task7 && bash verify/verify-admission.sh
```

Ожидаемый результат:
```
[PASS] privileged pod was rejected
[PASS] hostPath pod was rejected
[PASS] root-user pod was rejected
[PASS] secure pod 1 was accepted
[PASS] secure pod 2 was accepted
[PASS] secure pod 3 was accepted
Results: 6 passed, 0 failed
```

### Шаг 2 — Запустить скрипт валидации конфигурации
```bash
bash verify/validate-security.sh
```

### Шаг 3 — Ручная проверка
```bash
# Попытка создать привилегированный под — должна быть отклонена
kubectl apply -f insecure-manifests/01-privileged-pod.yaml

# Создание безопасного пода — должно пройти
kubectl apply -f secure-manifests/01-secure.yaml
kubectl get pod pod-secure-1 -n audit-zone
```

## Замечания

- Gatekeeper дублирует защиту PodSecurity Admission: первый слой — PodSecurity (встроен в apiserver), второй слой — Gatekeeper (Webhook). Оба активны в кластере.
- Namespace `kube-system`, `kube-public` и `gatekeeper-system` исключены из Gatekeeper-constraints, чтобы системные компоненты продолжали работать.
- Secure-манифесты используют `busybox` вместо `nginx`, так как nginx требует записи в `/var/run`, `/tmp`, `/var/cache/nginx` — что несовместимо с `readOnlyRootFilesystem: true` без дополнительных `emptyDir` volume (пример в `02-secure.yaml`).
