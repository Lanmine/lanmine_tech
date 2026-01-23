# Oxidized - Network Device Configuration Backup

## Overview

Oxidized automatically backs up network device configurations via SSH and stores them in a Git repository.

**Integration:** NetBox (dynamic device discovery via sidecar)

## Current Status

- **Deployed**: ✅ Running in oxidized namespace
- **Devices**: Synced from NetBox (currently 1 device: mgmt-sw-01)
- **Backup Interval**: Every 3600 seconds (1 hour)
- **Git Repository**: `/home/oxidized/.config/oxidized/configs.git`

## NetBox Integration (Sidecar Pattern)

### Architecture

```
┌─────────┐     API      ┌────────────────┐     Write     ┌─────────────┐
│ NetBox  │ ────────────>│ NetBox Sync    │ ────────────> │ router.db   │
│   API   │              │   Sidecar      │               │   (CSV)     │
└─────────┘              └────────────────┘               └─────────────┘
                                                                  │
                                                                  v Read
                                                           ┌─────────────┐
                                                           │  Oxidized   │
                                                           └─────────────┘
```

### How It Works

1. **NetBox Sync Sidecar** runs every 5 minutes
2. Queries NetBox API: `GET /api/dcim/devices/?status=active`
3. Transforms JSON to Oxidized CSV format:
   - Extracts: name, device_type.slug, primary_ip4.address
   - Strips CIDR notation from IP (10.0.99.101/24 → 10.0.99.101)
   - Writes: `name:model:ip` to `/oxidized-config/router.db`
4. Oxidized reads updated CSV and backs up devices

### Why Sidecar Instead of Direct HTTP?

- **Stability**: Oxidized's HTTP source couldn't parse NetBox's nested JSON
- **Simplicity**: CSV is Oxidized's native format
- **Transform Layer**: Handles IP CIDR stripping, model mapping
- **No Risk**: Keeps Oxidized using proven CSV source

### Configuration

**Sync Script**: `netbox-sync-configmap.yaml`
- Language: Python 3.11
- Dependencies: requests
- Sync Interval: 300 seconds (5 minutes)
- Output: `/oxidized-config/router.db`

**Environment Variables**:
- `NETBOX_URL`: http://netbox.netbox.svc.cluster.local:8080
- `NETBOX_TOKEN`: From secret `oxidized-secrets` (key: `netbox_token`)
- `SYNC_INTERVAL`: 300 (seconds)

**Shared Volume**:
- Type: emptyDir
- Name: `rendered-config`
- Mount in Oxidized: `/home/oxidized/.config/oxidized/`
- Mount in Sidecar: `/oxidized-config/`

## Adding Devices

### Via NetBox (Automatic)

1. Add device to NetBox via web UI or API
2. Set status to "active"
3. Assign primary IPv4 address
4. Wait up to 5 minutes for sync
5. Oxidized automatically discovers and backs up

### Manual Test

Force sync immediately:
```bash
kubectl exec -n oxidized deployment/oxidized -c netbox-sync -- python3 /scripts/sync.py &
```

Check synced devices:
```bash
kubectl exec -n oxidized deployment/oxidized -c oxidized -- cat /home/oxidized/.config/oxidized/router.db
```

## Monitoring

### Sidecar Logs

```bash
kubectl logs -n oxidized deployment/oxidized -c netbox-sync --tail=50
```

Expected output:
```
2026-01-23 08:39:04,103 - INFO - NetBox Sync starting - syncing every 300 seconds
2026-01-23 08:39:04,103 - INFO - Starting NetBox sync...
2026-01-23 08:39:04,270 - INFO - Found 1 active devices in NetBox
2026-01-23 08:39:04,270 - INFO - Added device: mgmt-sw-01 (catalyst-2960x) at 10.0.99.101
2026-01-23 08:39:04,271 - INFO - Successfully wrote /oxidized-config/router.db
2026-01-23 08:39:04,271 - INFO - Sync complete - 1 devices synced
```

### Oxidized Logs

```bash
kubectl logs -n oxidized deployment/oxidized -c oxidized --tail=50
```

### Backup Verification

Check Git repository:
```bash
kubectl exec -n oxidized deployment/oxidized -c oxidized -- \
  sh -c 'cd /home/oxidized/.config/oxidized/configs.git && git log --oneline | head -10'
```

## Credentials

Device SSH credentials stored in Vault and synced via secret:

```
secret/infrastructure/cisco-switch
├── user      # SSH username (admin)
├── password  # SSH password
```

Kubernetes secret: `oxidized-secrets`
- `ios_username`
- `ios_password`
- `ios_enable_password`
- `nxos_username`
- `nxos_password`
- `netbox_token`

## Model Mapping

Device type slug from NetBox maps to Oxidized model:

| NetBox device_type.slug | Oxidized Model |
|-------------------------|----------------|
| catalyst-2960x          | ios            |
| catalyst-3560cx         | ios            |
| catalyst-9300           | ios            |
| nexus-9300              | nxos           |
| nexus-93180yc-ex        | nxos           |

Configured in `oxidized-config` ConfigMap under `model_map`.

## Troubleshooting

### No devices synced

Check NetBox has active devices:
```bash
curl -H "Authorization: Token <token>" \
  http://netbox.netbox.svc.cluster.local:8080/api/dcim/devices/?status=active
```

### Sidecar crash loop

Check logs for errors:
```bash
kubectl logs -n oxidized deployment/oxidized -c netbox-sync --tail=100
```

Common issues:
- Invalid NetBox token
- NetBox API unreachable
- Missing primary_ip4 on devices

### Oxidized not backing up

1. Verify router.db exists and has correct format
2. Check Oxidized logs for SSH connection errors
3. Verify credentials in `oxidized-secrets` are correct
4. Check switch ACLs allow SSH from Kubernetes pod network

## Files

- `netbox-sync-configmap.yaml` - Python sync script
- Deployment: Managed in switch-ztp worktree (to be migrated)
- ConfigMaps: `oxidized-config`, `netbox-sync-script`
- Secrets: `oxidized-secrets`
- PVC: `oxidized-data` (Git repository storage)
