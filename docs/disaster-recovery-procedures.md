# Disaster Recovery Procedures

## Overview

This document describes disaster recovery procedures for the Lanmine.no infrastructure. All critical configurations are backed up and can be restored following these procedures.

## Backup Inventory

### 1. Network Device Configurations (Oxidized)

**What's backed up:**
- Switch configurations (mgmt-sw-01)
- Firewall configurations (OPNsense)
- Proxmox VE configuration

**Backup location:** Kubernetes PVC `oxidized-data` in `oxidized` namespace
**Backup frequency:** Every 30 minutes (automated)
**Retention:** All versions in Git history
**Encryption:** None (stored in cluster)

**Recovery procedure:**
```bash
# Access Oxidized web UI
open https://oxidized.lionfish-caiman.ts.net

# Or access via kubectl
kubectl exec -n oxidized deploy/oxidized -- sh -c \
  'cd /root/.config/oxidized && git show HEAD:mgmt-sw-01'

# To restore a switch config:
# 1. Copy config from Oxidized
# 2. SSH to switch
# 3. Paste config in global configuration mode
# 4. Save with 'write memory'
```

**Verification:**
```bash
# Check last backup time
curl -s http://oxidized.oxidized.svc.cluster.local:8888/nodes/stats.json | \
  jq '.nodes[] | {name, last_backup: .last.end, status: .last.status}'
```

### 2. Infrastructure Configurations (Ansible Backups)

**What's backed up:**
- OPNsense configuration (XML)
- Proxmox VE configuration (tar.gz)
- Vault file storage (tar.gz)
- PostgreSQL databases (pg_dump SQL)

**Backup location:** `ansible/backups/` directory in Git repository
**Backup frequency:** Weekly (automated via GitHub Actions)
**Retention:** 7 days of backups committed to Git
**Encryption:** age encryption (passphrase in Vault)

**Encrypted backups:**
```
ansible/backups/
├── opnsense/
│   └── config-YYYYMMDDTHHMMSS.xml.age
├── proxmox/
│   └── config-YYYYMMDDTHHMMSS.tar.gz.age
├── vault/
│   └── storage-YYYYMMDDTHHMMSS.tar.gz.age
└── postgres/
    └── dump-YYYYMMDDTHHMMSS.sql.age
```

**Recovery procedure:**

1. **Decrypt backup:**
```bash
# Get decryption key from Vault
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
export AGE_KEY=$(vault kv get -field=age_private_key secret/infrastructure/opnsense-backup)

# Decrypt backup
echo "$AGE_KEY" | age --decrypt -i - \
  ansible/backups/opnsense/config-20260101T120238.xml.age \
  > opnsense-config.xml

# Verify decryption
head -5 opnsense-config.xml  # Should show XML header
```

2. **Restore OPNsense:**
```bash
# Via WebUI: Diagnostics → Backup & Restore → Restore Configuration
# Upload decrypted XML file

# Or via CLI:
scp opnsense-config.xml root@10.0.10.1:/conf/config.xml
ssh root@10.0.10.1 '/etc/rc.reload_all'
```

3. **Restore Proxmox:**
```bash
# Decrypt backup
export AGE_KEY=$(vault kv get -field=age_private_key secret/infrastructure/proxmox-backup)
echo "$AGE_KEY" | age --decrypt -i - \
  ansible/backups/proxmox/config-20260101T120243.tar.gz.age \
  > proxmox-config.tar.gz

# Extract and restore
tar -xzf proxmox-config.tar.gz
scp -r etc/ root@10.0.10.5:/
ssh root@10.0.10.5 'systemctl restart pve*'
```

4. **Restore Vault:**
```bash
# Decrypt backup
export AGE_KEY=$(vault kv get -field=age_private_key secret/infrastructure/vault-backup)
echo "$AGE_KEY" | age --decrypt -i - \
  ansible/backups/vault/storage-20260101T120247.tar.gz.age \
  > vault-storage.tar.gz

# Stop Vault
ssh ubuntu@vault-01.lionfish-caiman.ts.net "sudo systemctl stop vault"

# Extract backup
ssh ubuntu@vault-01.lionfish-caiman.ts.net "sudo tar -xzf - -C /opt/vault/data" \
  < vault-storage.tar.gz

# Start Vault and unseal
ssh ubuntu@vault-01.lionfish-caiman.ts.net "sudo systemctl start vault"
vault operator unseal  # Repeat 3 times with different keys
```

5. **Restore PostgreSQL:**
```bash
# Decrypt backup
export AGE_KEY=$(vault kv get -field=age_private_key secret/infrastructure/postgres-backup)
echo "$AGE_KEY" | age --decrypt -i - \
  ansible/backups/postgres/dump-20260101T120251.sql.age \
  > postgres-dump.sql

# Restore database
psql -h postgres-01.lionfish-caiman.ts.net -U terraform < postgres-dump.sql
```

**Verification:**
```bash
# Check backup age
find ansible/backups/ -name "*.age" -type f -mtime -7 -ls

# Verify Git history
git log --oneline --all --grep="backup" | head -5

# Test decryption (without writing output)
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
for component in opnsense proxmox vault postgres; do
  echo "Testing $component backup decryption..."
  AGE_KEY=$(vault kv get -field=age_private_key secret/infrastructure/${component}-backup)
  LATEST=$(ls -t ansible/backups/$component/*.age 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    echo "$AGE_KEY" | age --decrypt -i - "$LATEST" | head -5
    echo "✅ $component: Decryption successful"
  fi
  echo
done
```

### 3. Kubernetes Cluster State

**What's backed up:**
- ArgoCD application definitions (Git)
- Helm values and manifests (Git)
- Longhorn volume snapshots (not automated)
- etcd snapshots (Talos automatic)

**Backup location:** Git repository `kubernetes/` directory
**Backup frequency:** Continuous (GitOps)
**Retention:** Full Git history
**Encryption:** None needed (public repo safe, secrets in Vault)

**Recovery procedure:**

1. **Reinstall Talos cluster** (if total cluster loss):
```bash
# Bootstrap control plane
talosctl apply-config --insecure \
  --nodes 10.0.10.30 \
  --file kubernetes/talos/controlplane.yaml

# Bootstrap Kubernetes
talosctl bootstrap --nodes 10.0.10.30

# Add workers
talosctl apply-config --insecure \
  --nodes 10.0.10.31 \
  --file kubernetes/talos/worker-01.yaml
talosctl apply-config --insecure \
  --nodes 10.0.10.32 \
  --file kubernetes/talos/worker-02.yaml
```

2. **Restore ArgoCD:**
```bash
# Install ArgoCD
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.5/manifests/install.yaml

# Apply infrastructure
kubectl apply -f kubernetes/infrastructure/

# ArgoCD will sync all applications automatically
```

3. **Restore secrets from Vault:**
```bash
# External Secrets Operator will sync automatically
# Verify sync
kubectl get externalsecrets -A
```

**Verification:**
```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Verify ArgoCD sync status
kubectl get applications -n argocd
```

### 4. Terraform State

**What's backed up:**
- Terraform state (PostgreSQL backend)
- PostgreSQL automatically backed up (see section 2)

**Backup location:** PostgreSQL database on postgres-01
**Backup frequency:** Real-time (automatic)
**Retention:** 7 days (via PostgreSQL backups)
**Encryption:** age encrypted in backups

**Recovery procedure:**
```bash
# Restore PostgreSQL first (see section 2.5)
# Terraform state will be available immediately after PostgreSQL restore

# Verify state
cd terraform && terraform state list
```

## Testing Recovery Procedures

### Monthly Tests (Recommended)

**Test 1: Decrypt and verify backup integrity**
```bash
cd ansible
./scripts/test-backup-restore.sh
```

**Test 2: Restore switch config to test device**
```bash
# Use a non-production switch
# Pull config from Oxidized
# Apply via SSH
# Verify functionality
```

**Test 3: Restore Kubernetes app from Git**
```bash
# Delete an application
kubectl delete -f kubernetes/apps/uptime-kuma/

# Wait 5 minutes for ArgoCD auto-sync
# Or trigger manual sync
argocd app sync uptime-kuma

# Verify restoration
kubectl get pods -n uptime-kuma
```

## Recovery Time Objectives (RTO)

| Component | RTO | Procedure |
|-----------|-----|-----------|
| Switch config | 15 min | Oxidized → SSH restore |
| OPNsense | 30 min | Decrypt backup → Upload XML → Reboot |
| Proxmox | 45 min | Decrypt → SCP → Restart services |
| Vault | 30 min | Decrypt → Extract → Unseal |
| PostgreSQL | 20 min | Decrypt → psql restore |
| Kubernetes app | 10 min | ArgoCD auto-sync or manual trigger |
| Full cluster | 2 hours | Talos reinstall → ArgoCD → Apps sync |

## Recovery Point Objectives (RPO)

| Component | RPO | Backup Frequency |
|-----------|-----|------------------|
| Switch configs | 30 min | Every 30 min (Oxidized) |
| Infrastructure | 7 days | Weekly (Ansible) |
| Kubernetes state | Real-time | GitOps (continuous) |
| Terraform state | Real-time | PostgreSQL backend |

## Critical Dependencies

### Vault Unsealing

**Requirement:** 3 of 5 unseal keys required
**Key storage:** Offline secure storage (not in backups)
**Recovery:** Must have physical access to unseal keys

**Emergency procedure if keys lost:**
1. Restore Vault data from backup
2. Vault will be sealed and inaccessible
3. If unseal keys are lost, Vault data is unrecoverable
4. Rebuild Vault from scratch, re-enter all secrets

### Age Encryption Keys

**Location:** Vault at `secret/infrastructure/*-backup` (4 separate keys)
- `secret/infrastructure/opnsense-backup` → age_private_key
- `secret/infrastructure/proxmox-backup` → age_private_key
- `secret/infrastructure/vault-backup` → age_private_key
- `secret/infrastructure/postgres-backup` → age_private_key

**Offline Backup:** `/home/ubuntu-mgmt01/age-private-keys-OFFLINE-BACKUP.txt`
- **CRITICAL**: Print this file and store in physical safe/vault
- **DO NOT** commit to Git or upload to cloud storage
- Required if Vault is completely lost

**Recovery:** If Vault is lost, age keys must be retrieved from offline backup

**Verify keys work:**
```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
AGE_KEY=$(vault kv get -field=age_private_key secret/infrastructure/opnsense-backup)
echo "$AGE_KEY" | age --decrypt -i - \
  ansible/backups/opnsense/config-*.age | head -5
# Should output valid XML
```

## Disaster Scenarios

### Scenario 1: Single Switch Failure

**Impact:** Network connectivity loss for connected devices
**Recovery:**
1. Replace failed switch hardware
2. Restore config from Oxidized (see section 1)
3. Verify connectivity

**RTO:** 30 minutes

### Scenario 2: Complete Proxmox Server Loss

**Impact:** All VMs offline
**Recovery:**
1. Reinstall Proxmox on replacement hardware
2. Restore Proxmox config (see section 2.3)
3. Restore VMs from Proxmox backups (if available)
4. Or rebuild VMs using Terraform

**RTO:** 4-8 hours

### Scenario 3: Kubernetes Cluster Failure

**Impact:** All containerized applications offline
**Recovery:**
1. Rebuild Talos cluster (see section 3.1)
2. ArgoCD auto-restores all applications
3. External Secrets syncs secrets from Vault

**RTO:** 2 hours

### Scenario 4: Vault Data Loss

**Impact:** Cannot decrypt backups, secrets lost
**Recovery:**
1. If Vault backup exists and can be decrypted: restore (see section 2.4)
2. If unseal keys available: recover Vault
3. If both lost: **Rebuild all secrets manually** (worst case)

**RTO:** 8+ hours (if rebuilding from scratch)

## Contacts and Escalation

**Primary contact:** tech@lanmine.no
**Escalation:** Lanmine board

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-24 | 1.0 | Initial disaster recovery procedures |
