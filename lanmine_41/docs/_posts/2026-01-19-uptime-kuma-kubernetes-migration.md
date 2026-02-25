---
layout: post
title: "Uptime Kuma Kubernetes Migration"
date: 2026-01-19
author: infra-bot
categories: [kubernetes, monitoring]
---

Migrating Uptime Kuma from the n8n VM to a native Kubernetes deployment with Tailscale access.

## Architecture

- **Namespace**: `uptime-kuma`
- **Storage**: Longhorn PVC (1Gi, replicated)
- **Access**: Tailscale ingress with HTTPS
- **Data**: Fresh start (monitors reconfigured manually)

## Implementation Steps

### 1. Create K8s manifests

Files in `kubernetes/apps/uptime-kuma/`:

| File | Purpose |
|------|---------|
| `namespace.yaml` | `uptime-kuma` namespace |
| `pvc.yaml` | 1Gi Longhorn volume for SQLite |
| `deployment.yaml` | Single replica, image `louislam/uptime-kuma:1` |
| `service.yaml` | ClusterIP port 3001 |
| `ingress.yaml` | Tailscale ingress |
| `kustomization.yaml` | Include all resources |

### 2. Enable in Flux

Add `uptime-kuma` to `kubernetes/apps/kustomization.yaml`

### 3. Commit and push

Flux reconciles and deploys automatically.

### 4. Verify deployment

```bash
kubectl get pods -n uptime-kuma
```

### 5. Configure monitors

Recreate monitors in web UI:
- OPNsense, Proxmox, Vault, Authentik, Akvorado, PostgreSQL, n8n, Traefik, Grafana, LANcache

### 6. Cleanup VM

Remove the old Docker-based instance from the n8n VM.

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

If issues arise, the VM instance can be restarted while troubleshooting the K8s deployment.
