# Uptime Kuma Kubernetes Migration

## Overview

Migrate Uptime Kuma from n8n VM (10.0.10.27:3001) to native Kubernetes deployment with Tailscale access.

## Architecture

- **Namespace**: `uptime-kuma`
- **Storage**: Longhorn PVC (1Gi, replicated)
- **Access**: `https://uptime.lionfish-caiman.ts.net`
- **Data**: Start fresh (no migration, monitors reconfigured manually)

## Implementation Steps

### 1. Create K8s manifests

Create/update files in `kubernetes/apps/uptime-kuma/`:

| File | Purpose |
|------|---------|
| `namespace.yaml` | `uptime-kuma` namespace |
| `pvc.yaml` | 1Gi Longhorn volume for SQLite |
| `deployment.yaml` | Single replica, image `louislam/uptime-kuma:1` |
| `service.yaml` | ClusterIP port 3001 |
| `ingress.yaml` | Tailscale ingress (replace existing proxy config) |
| `kustomization.yaml` | Include all resources |

### 2. Enable in Flux

Add `uptime-kuma` to `kubernetes/apps/kustomization.yaml`

### 3. Commit and push

- TruffleHog pre-commit hook scans for secrets automatically
- Flux reconciles and deploys

### 4. Verify deployment

- Check pod is running: `kubectl get pods -n uptime-kuma`
- Test Tailscale URL: `https://uptime.lionfish-caiman.ts.net`

### 5. Configure monitors

Recreate monitors in web UI based on `ansible/roles/uptime_kuma/defaults/main.yml`:
- OPNsense, Proxmox, Vault, Authentik, Akvorado, PostgreSQL, n8n, Traefik, Grafana, LANcache

### 6. Cleanup VM

```bash
ssh n8n 'docker compose -f /opt/uptime-kuma/docker-compose.yml down'
ssh n8n 'sudo rm -rf /opt/uptime-kuma'
```

## Resource Limits

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "50m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

## Rollback

If issues arise, the VM instance can be restarted:
```bash
ssh n8n 'docker compose -f /opt/uptime-kuma/docker-compose.yml up -d'
```
