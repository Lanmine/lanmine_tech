# Velero Kubernetes Backup

This directory contains Velero deployment for Kubernetes cluster backups using MinIO as the S3-compatible storage backend.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │   Velero    │───▶│    MinIO    │───▶│  Longhorn PVC   │ │
│  │  (backup)   │    │  (S3 API)   │    │   (100Gi)       │ │
│  └─────────────┘    └─────────────┘    └─────────────────┘ │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Backup Schedules                        │   │
│  │  • Hourly: critical namespaces (24h retention)      │   │
│  │  • Daily: full cluster (7-day retention)            │   │
│  │  • Weekly: full cluster (30-day retention)          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Create Vault Secrets

Before deploying, create the MinIO credentials in Vault:

```bash
# Generate secure credentials
ROOT_USER="minio-admin"
ROOT_PASSWORD=$(openssl rand -base64 32)

# Store in Vault
vault kv put secret/infrastructure/minio \
  root_user="$ROOT_USER" \
  root_password="$ROOT_PASSWORD"

# Verify
vault kv get secret/infrastructure/minio
```

### 2. Install Velero CRDs

```bash
# Install all Velero CRDs (required before deploying Velero)
for crd in backups backupstoragelocations deletebackuprequests downloadrequests \
           podvolumebackups podvolumerestores restores schedules \
           serverstatusrequests volumesnapshotlocations backuprepositories; do
  kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/v1.13.0/config/crd/v1/bases/velero.io_${crd}.yaml
done
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/v1.13.0/config/crd/v2alpha1/bases/velero.io_datauploads.yaml
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/v1.13.0/config/crd/v2alpha1/bases/velero.io_datadownloads.yaml
```

### 3. Deploy MinIO First

```bash
kubectl apply -k kubernetes/infrastructure/minio/
```

Wait for MinIO to be ready:

```bash
kubectl -n minio wait --for=condition=ready pod -l app=minio --timeout=300s
```

### 4. Deploy Velero

```bash
kubectl apply -k kubernetes/infrastructure/velero/
```

## Backup Schedules

| Schedule | Frequency | Retention | Scope |
|----------|-----------|-----------|-------|
| `hourly-critical-backup` | Every hour | 24 hours | monitoring, argocd, netbox, uptime-kuma, velero |
| `daily-full-backup` | 2 AM daily | 7 days | All namespaces (except kube-*) |
| `weekly-full-backup` | 3 AM Sunday | 30 days | All namespaces (except kube-*) |

## Usage

### Check Backup Status

```bash
# List all backups
velero backup get

# Describe a specific backup
velero backup describe daily-full-backup-<timestamp>

# View backup logs
velero backup logs daily-full-backup-<timestamp>
```

### Manual Backup

```bash
# Backup entire cluster
velero backup create manual-backup-$(date +%Y%m%d)

# Backup specific namespace
velero backup create netbox-backup --include-namespaces netbox
```

### Restore from Backup

```bash
# List available backups
velero backup get

# Restore entire backup
velero restore create --from-backup daily-full-backup-<timestamp>

# Restore specific namespace
velero restore create --from-backup daily-full-backup-<timestamp> \
  --include-namespaces netbox

# Restore to different namespace
velero restore create --from-backup daily-full-backup-<timestamp> \
  --include-namespaces netbox \
  --namespace-mappings netbox:netbox-restored
```

### Disaster Recovery

For full cluster recovery, see `/docs/disaster-recovery-procedures.md`.

## Monitoring

Velero exposes Prometheus metrics at `:8085/metrics`. Alerts are configured in `monitoring-alerts.yaml`:

- `VeleroBackupFailed` - Backup failed completely
- `VeleroBackupPartiallyFailed` - Some items not backed up
- `VeleroNoRecentBackup` - No successful backup in 25 hours
- `VeleroBackupStorageLocationUnavailable` - MinIO unreachable

## Troubleshooting

### Backup Stuck in Progress

```bash
# Check velero logs
kubectl -n velero logs -l app.kubernetes.io/name=velero

# Check backup details
velero backup describe <backup-name> --details
```

### Storage Location Unavailable

```bash
# Check MinIO is running
kubectl -n minio get pods

# Test MinIO connectivity
kubectl -n velero exec -it deploy/velero -- \
  wget -qO- http://minio.minio.svc.cluster.local:9000/minio/health/ready

# Check credentials
kubectl -n velero get secret velero-credentials -o yaml
```

### Restore Fails

```bash
# Check restore status
velero restore describe <restore-name> --details

# View restore logs
velero restore logs <restore-name>
```
