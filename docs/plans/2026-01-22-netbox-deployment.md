# NetBox Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy NetBox to Kubernetes as network inventory source of truth with switch integration

**Architecture:** NetBox runs on Kubernetes with PostgreSQL (postgres-01), Redis cache, dual ingress (Cloudflare + Tailscale), and Vault-managed secrets. Initial data includes mgmt-sw-01 registration.

**Tech Stack:** NetBox v4.2, PostgreSQL (existing), Redis 7, Kubernetes, ArgoCD, cert-manager, external-dns

---

## Task 1: Create Vault Secrets for NetBox

**Files:**
- Vault: `secret/infrastructure/netbox`

**Step 1: Generate NetBox secret key**

```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')
echo $SECRET_KEY
```

Expected: Random 50-character string

**Step 2: Create PostgreSQL database and user**

```bash
# Connect to postgres-01
ssh ubuntu-mgmt01@10.0.10.23 'sudo -u postgres psql' << 'EOF'
CREATE DATABASE netbox;
CREATE USER netbox WITH PASSWORD 'CHANGE_ME_GENERATED';
GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;
\c netbox
GRANT ALL ON SCHEMA public TO netbox;
EOF
```

Expected: Database and user created

**Step 3: Store secrets in Vault**

```bash
vault kv put secret/infrastructure/netbox \
  secret_key="$SECRET_KEY" \
  db_host="10.0.10.23" \
  db_port="5432" \
  db_name="netbox" \
  db_user="netbox" \
  db_password="CHANGE_ME_GENERATED" \
  redis_host="netbox-redis" \
  redis_port="6379" \
  allowed_hosts="*" \
  superuser_name="admin" \
  superuser_email="admin@lanmine.no" \
  superuser_password="CHANGE_ME_ADMIN" \
  superuser_api_token="CHANGE_ME_TOKEN_GENERATED"
```

Expected: Key "secret/infrastructure/netbox" written successfully

**Step 4: Verify secrets**

```bash
vault kv get secret/infrastructure/netbox
```

Expected: All keys displayed

**Step 5: Commit**

No commit - Vault changes only

---

## Task 2: Create NetBox Namespace and Resources

**Files:**
- Create: `kubernetes/apps/netbox/namespace.yaml`
- Create: `kubernetes/apps/netbox/kustomization.yaml`

**Step 1: Create namespace manifest**

```yaml
# kubernetes/apps/netbox/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: netbox
  labels:
    name: netbox
```

**Step 2: Create kustomization**

```yaml
# kubernetes/apps/netbox/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: netbox

resources:
  - namespace.yaml
  - secrets.yaml
  - redis.yaml
  - deployment.yaml
  - service.yaml
  - ingress-tailscale.yaml
  - ingress-cloudflare.yaml
```

**Step 3: Verify YAML syntax**

```bash
kubectl kustomize kubernetes/apps/netbox --dry-run=client
```

Expected: No errors

**Step 4: Commit**

```bash
git add kubernetes/apps/netbox/namespace.yaml kubernetes/apps/netbox/kustomization.yaml
git commit -m "feat: add NetBox namespace and kustomization"
```

---

## Task 3: Create Kubernetes Secrets from Vault

**Files:**
- Create: `kubernetes/apps/netbox/secrets.yaml`

**Step 1: Create external secrets manifest**

```yaml
# kubernetes/apps/netbox/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: netbox-secrets
  namespace: netbox
type: Opaque
stringData:
  secret_key: "PLACEHOLDER"
  db_password: "PLACEHOLDER"
  superuser_password: "PLACEHOLDER"
  superuser_api_token: "PLACEHOLDER"
---
apiVersion: v1
kind: Secret
metadata:
  name: netbox-db-config
  namespace: netbox
type: Opaque
stringData:
  DB_HOST: "10.0.10.23"
  DB_PORT: "5432"
  DB_NAME: "netbox"
  DB_USER: "netbox"
  REDIS_HOST: "netbox-redis"
  REDIS_PORT: "6379"
  REDIS_DATABASE: "0"
  REDIS_CACHE_DATABASE: "1"
```

**Step 2: Create script to populate from Vault**

```bash
# kubernetes/apps/netbox/sync-secrets.sh
#!/bin/bash
set -euo pipefail

export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"

SECRET_KEY=$(vault kv get -field=secret_key secret/infrastructure/netbox)
DB_PASSWORD=$(vault kv get -field=db_password secret/infrastructure/netbox)
SUPERUSER_PASSWORD=$(vault kv get -field=superuser_password secret/infrastructure/netbox)
SUPERUSER_API_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)

kubectl create secret generic netbox-secrets \
  --from-literal=secret_key="$SECRET_KEY" \
  --from-literal=db_password="$DB_PASSWORD" \
  --from-literal=superuser_password="$SUPERUSER_PASSWORD" \
  --from-literal=superuser_api_token="$SUPERUSER_API_TOKEN" \
  --namespace=netbox \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets synced from Vault to netbox namespace"
```

**Step 3: Make script executable**

```bash
chmod +x kubernetes/apps/netbox/sync-secrets.sh
```

**Step 4: Commit**

```bash
git add kubernetes/apps/netbox/secrets.yaml kubernetes/apps/netbox/sync-secrets.sh
git commit -m "feat: add NetBox secrets configuration"
```

---

## Task 4: Deploy Redis Cache

**Files:**
- Create: `kubernetes/apps/netbox/redis.yaml`

**Step 1: Create Redis deployment and service**

```yaml
# kubernetes/apps/netbox/redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netbox-redis
  namespace: netbox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: netbox-redis
  template:
    metadata:
      labels:
        app: netbox-redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
              name: redis
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
          volumeMounts:
            - name: redis-data
              mountPath: /data
      volumes:
        - name: redis-data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: netbox-redis
  namespace: netbox
spec:
  selector:
    app: netbox-redis
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  type: ClusterIP
```

**Step 2: Validate manifest**

```bash
kubectl apply --dry-run=client -f kubernetes/apps/netbox/redis.yaml
```

Expected: No errors

**Step 3: Commit**

```bash
git add kubernetes/apps/netbox/redis.yaml
git commit -m "feat: add Redis deployment for NetBox cache"
```

---

## Task 5: Create NetBox Deployment

**Files:**
- Create: `kubernetes/apps/netbox/deployment.yaml`

**Step 1: Create deployment manifest**

```yaml
# kubernetes/apps/netbox/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netbox
  namespace: netbox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: netbox
  template:
    metadata:
      labels:
        app: netbox
    spec:
      initContainers:
        - name: netbox-init
          image: netboxcommunity/netbox:v4.2
          command:
            - /bin/sh
            - -c
            - |
              /opt/netbox/netbox/manage.py migrate
              /opt/netbox/netbox/manage.py collectstatic --no-input
          env:
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: netbox-secrets
                  key: secret_key
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_HOST
            - name: DB_PORT
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_PORT
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_NAME
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: netbox-secrets
                  key: db_password
            - name: REDIS_HOST
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_HOST
            - name: REDIS_PORT
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_PORT
            - name: REDIS_DATABASE
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_DATABASE
            - name: REDIS_CACHE_DATABASE
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_CACHE_DATABASE
          volumeMounts:
            - name: netbox-media
              mountPath: /opt/netbox/netbox/media
            - name: netbox-static
              mountPath: /opt/netbox/netbox/static
      containers:
        - name: netbox
          image: netboxcommunity/netbox:v4.2
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: netbox-secrets
                  key: secret_key
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_HOST
            - name: DB_PORT
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_PORT
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_NAME
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: DB_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: netbox-secrets
                  key: db_password
            - name: REDIS_HOST
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_HOST
            - name: REDIS_PORT
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_PORT
            - name: REDIS_DATABASE
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_DATABASE
            - name: REDIS_CACHE_DATABASE
              valueFrom:
                secretKeyRef:
                  name: netbox-db-config
                  key: REDIS_CACHE_DATABASE
            - name: SUPERUSER_NAME
              value: "admin"
            - name: SUPERUSER_EMAIL
              value: "admin@lanmine.no"
            - name: SUPERUSER_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: netbox-secrets
                  key: superuser_password
            - name: SUPERUSER_API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: netbox-secrets
                  key: superuser_api_token
          volumeMounts:
            - name: netbox-media
              mountPath: /opt/netbox/netbox/media
            - name: netbox-static
              mountPath: /opt/netbox/netbox/static
          resources:
            requests:
              memory: "512Mi"
              cpu: "200m"
            limits:
              memory: "1Gi"
              cpu: "500m"
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: netbox-media
          emptyDir: {}
        - name: netbox-static
          emptyDir: {}
```

**Step 2: Validate manifest**

```bash
kubectl apply --dry-run=client -f kubernetes/apps/netbox/deployment.yaml
```

Expected: No errors

**Step 3: Commit**

```bash
git add kubernetes/apps/netbox/deployment.yaml
git commit -m "feat: add NetBox deployment with init container"
```

---

## Task 6: Create Service

**Files:**
- Create: `kubernetes/apps/netbox/service.yaml`

**Step 1: Create service manifest**

```yaml
# kubernetes/apps/netbox/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: netbox
  namespace: netbox
spec:
  selector:
    app: netbox
  ports:
    - port: 8080
      targetPort: 8080
      name: http
  type: ClusterIP
```

**Step 2: Validate manifest**

```bash
kubectl apply --dry-run=client -f kubernetes/apps/netbox/service.yaml
```

Expected: No errors

**Step 3: Commit**

```bash
git add kubernetes/apps/netbox/service.yaml
git commit -m "feat: add NetBox service"
```

---

## Task 7: Create Tailscale Ingress

**Files:**
- Create: `kubernetes/apps/netbox/ingress-tailscale.yaml`

**Step 1: Create Tailscale ingress**

```yaml
# kubernetes/apps/netbox/ingress-tailscale.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: netbox-tailscale
  namespace: netbox
  annotations:
    cert-manager.io/cluster-issuer: lanmine-ca-issuer
spec:
  ingressClassName: tailscale
  tls:
    - hosts:
        - netbox
      secretName: netbox-tailscale-tls
  rules:
    - host: netbox
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: netbox
                port:
                  number: 8080
```

**Step 2: Validate manifest**

```bash
kubectl apply --dry-run=client -f kubernetes/apps/netbox/ingress-tailscale.yaml
```

Expected: No errors

**Step 3: Commit**

```bash
git add kubernetes/apps/netbox/ingress-tailscale.yaml
git commit -m "feat: add NetBox Tailscale ingress"
```

---

## Task 8: Create Cloudflare Ingress

**Files:**
- Create: `kubernetes/apps/netbox/ingress-cloudflare.yaml`

**Step 1: Create Cloudflare ingress**

```yaml
# kubernetes/apps/netbox/ingress-cloudflare.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: netbox-cloudflare
  namespace: netbox
  annotations:
    external-dns.alpha.kubernetes.io/hostname: netbox.hl0.dev
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - netbox.hl0.dev
      secretName: netbox-hl0-tls
  rules:
    - host: netbox.hl0.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: netbox
                port:
                  number: 8080
```

**Step 2: Validate manifest**

```bash
kubectl apply --dry-run=client -f kubernetes/apps/netbox/ingress-cloudflare.yaml
```

Expected: No errors

**Step 3: Commit**

```bash
git add kubernetes/apps/netbox/ingress-cloudflare.yaml
git commit -m "feat: add NetBox Cloudflare ingress with Let's Encrypt"
```

---

## Task 9: Deploy NetBox to Kubernetes

**Files:**
- Modify: `kubernetes/apps/kustomization.yaml`

**Step 1: Run secret sync script**

```bash
cd kubernetes/apps/netbox
./sync-secrets.sh
```

Expected: "Secrets synced from Vault to netbox namespace"

**Step 2: Apply namespace and secrets**

```bash
kubectl apply -f kubernetes/apps/netbox/namespace.yaml
kubectl apply -f kubernetes/apps/netbox/secrets.yaml
```

Expected: namespace/netbox created, secrets created

**Step 3: Deploy Redis**

```bash
kubectl apply -f kubernetes/apps/netbox/redis.yaml
```

Expected: deployment.apps/netbox-redis created, service/netbox-redis created

**Step 4: Wait for Redis to be ready**

```bash
kubectl wait --for=condition=available --timeout=120s deployment/netbox-redis -n netbox
```

Expected: deployment.apps/netbox-redis condition met

**Step 5: Deploy NetBox**

```bash
kubectl apply -f kubernetes/apps/netbox/deployment.yaml
kubectl apply -f kubernetes/apps/netbox/service.yaml
```

Expected: deployment.apps/netbox created, service/netbox created

**Step 6: Wait for NetBox to be ready**

```bash
kubectl wait --for=condition=available --timeout=300s deployment/netbox -n netbox
```

Expected: deployment.apps/netbox condition met

**Step 7: Check pod status**

```bash
kubectl get pods -n netbox
```

Expected: netbox pod Running, redis pod Running

**Step 8: Deploy ingresses**

```bash
kubectl apply -f kubernetes/apps/netbox/ingress-tailscale.yaml
kubectl apply -f kubernetes/apps/netbox/ingress-cloudflare.yaml
```

Expected: ingresses created

**Step 9: Add to apps kustomization**

```bash
# Edit kubernetes/apps/kustomization.yaml, add:
  - netbox
```

**Step 10: Commit**

```bash
git add kubernetes/apps/kustomization.yaml
git commit -m "feat: add NetBox to apps kustomization"
```

---

## Task 10: Create ArgoCD Application

**Files:**
- Create: `kubernetes/argocd/apps/netbox.yaml`

**Step 1: Create ArgoCD application manifest**

```yaml
# kubernetes/argocd/apps/netbox.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: netbox
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Lanmine/lanmine_tech
    targetRevision: HEAD
    path: kubernetes/apps/netbox
  destination:
    server: https://kubernetes.default.svc
    namespace: netbox
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Step 2: Apply ArgoCD application**

```bash
kubectl apply -f kubernetes/argocd/apps/netbox.yaml
```

Expected: application.argoproj.io/netbox created

**Step 3: Wait for sync**

```bash
kubectl wait --for=condition=Synced --timeout=300s application/netbox -n argocd
```

Expected: application.argoproj.io/netbox condition met

**Step 4: Commit**

```bash
git add kubernetes/argocd/apps/netbox.yaml
git commit -m "feat: add NetBox ArgoCD application"
```

---

## Task 11: Verify NetBox Deployment

**Files:**
- None (verification only)

**Step 1: Check pod logs**

```bash
kubectl logs -n netbox deployment/netbox --tail=50
```

Expected: No errors, application started

**Step 2: Test Tailscale access**

```bash
curl -k https://netbox.lionfish-caiman.ts.net/ | grep NetBox
```

Expected: HTML containing "NetBox"

**Step 3: Test Cloudflare access**

```bash
curl https://netbox.hl0.dev/ | grep NetBox
```

Expected: HTML containing "NetBox"

**Step 4: Test login**

```bash
# Get superuser credentials from Vault
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
ADMIN_USER=$(vault kv get -field=superuser_name secret/infrastructure/netbox)
ADMIN_PASS=$(vault kv get -field=superuser_password secret/infrastructure/netbox)
echo "Login: $ADMIN_USER / $ADMIN_PASS"
```

Expected: Credentials displayed

**Step 5: Access web UI**

Open: https://netbox.lionfish-caiman.ts.net
Login with admin credentials

Expected: NetBox dashboard visible

**Step 6: No commit**

Verification only

---

## Task 12: Register mgmt-sw-01 in NetBox

**Files:**
- Create: `kubernetes/apps/netbox/init-data.py`

**Step 1: Create Python script for initial data**

```python
# kubernetes/apps/netbox/init-data.py
#!/usr/bin/env python3
"""
Initialize NetBox with switch inventory from Ansible
"""
import os
import requests
import yaml

NETBOX_URL = os.getenv("NETBOX_URL", "https://netbox.lionfish-caiman.ts.net")
NETBOX_TOKEN = os.getenv("NETBOX_TOKEN")

if not NETBOX_TOKEN:
    print("Error: NETBOX_TOKEN not set")
    exit(1)

headers = {
    "Authorization": f"Token {NETBOX_TOKEN}",
    "Content-Type": "application/json",
}

# Load switch inventory
with open("../../ansible/inventory/switches.yml") as f:
    inventory = yaml.safe_load(f)

# Create site
site_data = {
    "name": "Lanmine Datacenter",
    "slug": "lanmine-dc",
    "status": "active",
}
resp = requests.post(f"{NETBOX_URL}/api/dcim/sites/", json=site_data, headers=headers)
if resp.status_code in [200, 201]:
    site_id = resp.json()["id"]
    print(f"Site created: {site_id}")
else:
    # Site might already exist
    resp = requests.get(f"{NETBOX_URL}/api/dcim/sites/?slug=lanmine-dc", headers=headers)
    site_id = resp.json()["results"][0]["id"]
    print(f"Site exists: {site_id}")

# Create manufacturer
mfr_data = {
    "name": "Cisco",
    "slug": "cisco",
}
resp = requests.post(f"{NETBOX_URL}/api/dcim/manufacturers/", json=mfr_data, headers=headers)
if resp.status_code in [200, 201]:
    mfr_id = resp.json()["id"]
    print(f"Manufacturer created: {mfr_id}")
else:
    resp = requests.get(f"{NETBOX_URL}/api/dcim/manufacturers/?slug=cisco", headers=headers)
    mfr_id = resp.json()["results"][0]["id"]
    print(f"Manufacturer exists: {mfr_id}")

# Create device type
for switch in inventory["switches"]:
    model = switch["model"]
    device_type_data = {
        "manufacturer": mfr_id,
        "model": model.upper(),
        "slug": model.lower(),
    }
    resp = requests.post(f"{NETBOX_URL}/api/dcim/device-types/", json=device_type_data, headers=headers)
    if resp.status_code in [200, 201]:
        device_type_id = resp.json()["id"]
        print(f"Device type created: {device_type_id}")
    else:
        resp = requests.get(f"{NETBOX_URL}/api/dcim/device-types/?slug={model.lower()}", headers=headers)
        device_type_id = resp.json()["results"][0]["id"]
        print(f"Device type exists: {device_type_id}")

    # Create device role
    role_data = {
        "name": switch["role"].capitalize(),
        "slug": switch["role"],
        "color": "9e9e9e",
    }
    resp = requests.post(f"{NETBOX_URL}/api/dcim/device-roles/", json=role_data, headers=headers)
    if resp.status_code in [200, 201]:
        role_id = resp.json()["id"]
        print(f"Device role created: {role_id}")
    else:
        resp = requests.get(f"{NETBOX_URL}/api/dcim/device-roles/?slug={switch['role']}", headers=headers)
        role_id = resp.json()["results"][0]["id"]
        print(f"Device role exists: {role_id}")

    # Create device
    device_data = {
        "name": switch["hostname"],
        "device_type": device_type_id,
        "role": role_id,
        "site": site_id,
        "serial": switch["serial"],
        "status": "active",
    }
    resp = requests.post(f"{NETBOX_URL}/api/dcim/devices/", json=device_data, headers=headers)
    if resp.status_code in [200, 201]:
        device_id = resp.json()["id"]
        print(f"Device created: {switch['hostname']} ({device_id})")
    else:
        print(f"Error creating device {switch['hostname']}: {resp.status_code} - {resp.text}")
        continue

    # Create management interface
    iface_data = {
        "device": device_id,
        "name": "Vlan99",
        "type": "virtual",
        "enabled": True,
        "mgmt_only": True,
    }
    resp = requests.post(f"{NETBOX_URL}/api/dcim/interfaces/", json=iface_data, headers=headers)
    if resp.status_code in [200, 201]:
        iface_id = resp.json()["id"]
        print(f"Interface created: Vlan99 ({iface_id})")

        # Assign IP address
        ip_data = {
            "address": f"{switch['mgmt_ip']}/24",
            "status": "active",
            "assigned_object_type": "dcim.interface",
            "assigned_object_id": iface_id,
        }
        resp = requests.post(f"{NETBOX_URL}/api/ipam/ip-addresses/", json=ip_data, headers=headers)
        if resp.status_code in [200, 201]:
            ip_id = resp.json()["id"]
            print(f"IP assigned: {switch['mgmt_ip']} ({ip_id})")

            # Set as primary IP
            device_update = {
                "primary_ip4": ip_id,
            }
            resp = requests.patch(f"{NETBOX_URL}/api/dcim/devices/{device_id}/", json=device_update, headers=headers)
            if resp.status_code == 200:
                print(f"Primary IP set for {switch['hostname']}")

print("\nNetBox initialization complete!")
```

**Step 2: Make script executable**

```bash
chmod +x kubernetes/apps/netbox/init-data.py
```

**Step 3: Install dependencies**

```bash
pip3 install requests pyyaml
```

**Step 4: Get API token from Vault**

```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
export NETBOX_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)
```

**Step 5: Run initialization script**

```bash
cd kubernetes/apps/netbox
python3 init-data.py
```

Expected: Site, manufacturer, device type, role, and device created

**Step 6: Verify in NetBox UI**

Open: https://netbox.lionfish-caiman.ts.net/dcim/devices/
Check: mgmt-sw-01 visible with IP 10.0.99.101

**Step 7: Commit**

```bash
git add kubernetes/apps/netbox/init-data.py
git commit -m "feat: add NetBox initialization script for switch inventory"
```

---

## Task 13: Update CLAUDE.md Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add NetBox section after Kubernetes Cluster**

Find line containing "## Kubernetes Cluster" and add after the Tailscale Services table:

```markdown
### NetBox (Network Inventory)

NetBox is the source of truth for network infrastructure inventory, IPAM, and DCIM.

**Access:**
- Tailscale: https://netbox.lionfish-caiman.ts.net
- Cloudflare: https://netbox.hl0.dev
- API: https://netbox.hl0.dev/api/

**Credentials:** Vault at `secret/infrastructure/netbox`

**Components:**
- Database: PostgreSQL on postgres-01 (10.0.10.23)
- Cache: Redis in netbox namespace
- Storage: emptyDir (media/static)

**Integration:**
- Ansible dynamic inventory: Switch data source
- Oxidized: Device list via API
- SNMP exporter: Target discovery
- ZTP: Switch registration post-provisioning

**Registered Devices:**
- mgmt-sw-01 (10.0.99.101) - Catalyst 2960X access switch
```

**Step 2: Verify documentation**

```bash
grep -A 10 "NetBox" CLAUDE.md
```

Expected: NetBox section visible

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add NetBox section to CLAUDE.md"
```

---

## Post-Deployment Verification

**Manual checks:**
1. NetBox accessible via both Tailscale and Cloudflare URLs
2. Login works with admin credentials from Vault
3. mgmt-sw-01 visible in Devices list
4. IP address 10.0.99.101 assigned to Vlan99 interface
5. ArgoCD shows NetBox application healthy and synced

**Commands:**
```bash
# Check pod status
kubectl get pods -n netbox

# Check ingresses
kubectl get ingress -n netbox

# Check ArgoCD
kubectl get application -n argocd netbox

# Test API
export NETBOX_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)
curl -H "Authorization: Token $NETBOX_TOKEN" https://netbox.hl0.dev/api/dcim/devices/
```

**Expected:**
- All pods Running
- Ingresses show ADDRESS assigned
- ArgoCD application Healthy and Synced
- API returns mgmt-sw-01 device

---

## Next Steps

After NetBox is deployed and mgmt-sw-01 is registered:

1. **Oxidized Integration** - Pull device list from NetBox API
2. **Ansible Dynamic Inventory** - Replace static `switches.yml` with NetBox query
3. **SNMP Exporter** - Auto-discover targets from NetBox
4. **ZTP Enhancement** - Auto-register new switches in NetBox post-provisioning
