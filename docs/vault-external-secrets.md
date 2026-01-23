# Vault Integration with External Secrets Operator

## Overview

External Secrets Operator (ESO) automatically syncs secrets from HashiCorp Vault to Kubernetes secrets. This eliminates manual sync scripts and ensures secrets stay up-to-date.

**Key Benefits:**
- ✅ Single source of truth (Vault)
- ✅ Automatic sync every 5 minutes
- ✅ Secrets never stored in Kubernetes etcd permanently
- ✅ Audit trail in Vault
- ✅ No manual sync scripts needed

## Architecture

```
┌─────────────┐     Read      ┌──────────────────┐     Create/Update   ┌─────────────────┐
│ Vault       │ <────────────>│ External Secrets │ ──────────────────> │ Kubernetes      │
│             │               │ Operator         │                     │ Secrets         │
│ (Source of  │               │                  │                     │ (ephemeral)     │
│  Truth)     │               │ Refresh: 5m      │                     │                 │
└─────────────┘               └──────────────────┘                     └─────────────────┘
```

## Current Setup

### ClusterSecretStore

**Name:** `vault`
**Scope:** Cluster-wide (all namespaces)
**Vault Server:** https://vault-01.lionfish-caiman.ts.net:8200
**KV Version:** v2
**Path:** `secret`
**Authentication:** Token (from secret `vault-token` in `external-secrets` namespace)

```bash
# View ClusterSecretStore
kubectl get clustersecretstore vault -o yaml
```

### Managed Secrets

| Namespace | ExternalSecret | Vault Path | Keys | Status |
|-----------|----------------|------------|------|--------|
| oxidized | oxidized-secrets | secret/infrastructure/cisco-switch<br>secret/infrastructure/netbox<br>secret/infrastructure/oxidized | ios_username<br>ios_password<br>ios_enable_password<br>nxos_username<br>nxos_password<br>netbox_token<br>oxidized_password | ✅ Active |
| cert-manager | cloudflare-api-token | secret/infrastructure/cloudflare | api-token | ✅ Active |
| external-dns | cloudflare-api-token | secret/infrastructure/cloudflare | api-token | ✅ Active |
| monitoring | grafana-admin | secret/infrastructure/grafana | username<br>password | ✅ Active |
| monitoring | grafana-oauth | secret/infrastructure/authentik | grafana_client_id<br>grafana_client_secret | ✅ Active |
| monitoring | alertmanager-smtp | secret/infrastructure/smtp | smtp_* | ✅ Active |
| opnsense-exporter | opnsense-exporter-credentials | secret/infrastructure/opnsense | api_key<br>api_secret | ✅ Active |
| tailscale | operator-oauth | secret/infrastructure/tailscale | oauth_* | ✅ Active |
| crowdsec | crowdsec-* | secret/infrastructure/crowdsec | * | ✅ Active |

## Adding New ExternalSecrets

### 1. Store Secret in Vault

```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"

# Store secret
vault kv put secret/infrastructure/my-service \
  username="myuser" \
  password="mypassword" \
  api_token="mytoken"
```

### 2. Create ExternalSecret Manifest

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-credentials
  namespace: my-namespace
spec:
  refreshInterval: 5m  # Sync every 5 minutes
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: my-service-credentials  # Kubernetes secret name
    creationPolicy: Owner  # ESO owns this secret
  data:
    # Map Vault keys to Kubernetes secret keys
    - secretKey: username
      remoteRef:
        key: secret/infrastructure/my-service
        property: username
    - secretKey: password
      remoteRef:
        key: secret/infrastructure/my-service
        property: password
    - secretKey: api-token
      remoteRef:
        key: secret/infrastructure/my-service
        property: api_token
```

### 3. Apply Manifest

```bash
kubectl apply -f external-secret.yaml
```

### 4. Verify Sync

```bash
# Check ExternalSecret status
kubectl get externalsecret -n my-namespace my-service-credentials

# Expected output:
# NAME                      STORETYPE            STORE   REFRESH INTERVAL   STATUS         READY
# my-service-credentials    ClusterSecretStore   vault   5m                 SecretSynced   True

# Verify Kubernetes secret created
kubectl get secret -n my-namespace my-service-credentials

# Check secret contents
kubectl get secret -n my-namespace my-service-credentials -o yaml
```

## Secret Rotation

When you update a secret in Vault, External Secrets automatically syncs it:

```bash
# Update secret in Vault
vault kv put secret/infrastructure/my-service \
  username="myuser" \
  password="newpassword"

# Wait up to 5 minutes for automatic sync
# OR force immediate sync
kubectl annotate externalsecret my-service-credentials \
  -n my-namespace \
  force-sync=$(date +%s) --overwrite
```

**Note:** Updating a Kubernetes secret doesn't automatically restart pods. To pick up new credentials:

```bash
kubectl rollout restart deployment/my-app -n my-namespace
```

## Troubleshooting

### ExternalSecret Status Not Ready

```bash
# Check ExternalSecret events
kubectl describe externalsecret my-service -n my-namespace

# Common issues:
# - "SecretStoreRefNotFound": ClusterSecretStore doesn't exist
# - "SecretSyncedError": Can't read from Vault (check token, path)
# - "SecretSyncedError: key not found": Vault path doesn't exist
```

### Vault Token Expired

```bash
# Check ClusterSecretStore status
kubectl get clustersecretstore vault

# If invalid, renew token
vault token renew

# Update token secret
kubectl create secret generic vault-token \
  --from-literal=token="<new-token>" \
  --namespace=external-secrets \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Secret Not Syncing

```bash
# Check ESO logs
kubectl logs -n external-secrets deployment/external-secrets --tail=50

# Force sync
kubectl annotate externalsecret my-service \
  -n my-namespace \
  force-sync=$(date +%s) --overwrite
```

## Vault Paths in Use

```
secret/infrastructure/
├── argocd                  # ArgoCD admin credentials
├── authentik               # Authentik OAuth credentials
├── cisco-switch            # Switch SSH credentials (ios_*, nxos_*)
├── cloudflare              # Cloudflare API tokens
├── crowdsec                # CrowdSec bouncer keys
├── github                  # GitHub tokens
├── grafana                 # Grafana admin credentials
├── netbox                  # NetBox API token
├── opnsense                # OPNsense API credentials
├── oxidized                # Oxidized web password
├── postgres                # PostgreSQL credentials
├── proxmox                 # Proxmox API credentials
├── smtp                    # SMTP server credentials
├── ssh                     # SSH keys and credentials
├── tailscale               # Tailscale OAuth credentials
└── switches/
    └── global              # Global switch credentials (SNMPv3, etc.)
```

## Migration from Manual Sync Scripts

**Old Pattern:**
```bash
# sync-secrets.sh
IOS_USERNAME=$(vault kv get -field=user secret/infrastructure/cisco-switch)
kubectl create secret generic oxidized-secrets \
  --from-literal=ios_username="$IOS_USERNAME" \
  --namespace=oxidized \
  --dry-run=client -o yaml | kubectl apply -f -
```

**New Pattern:**
```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: oxidized-secrets
  namespace: oxidized
spec:
  data:
    - secretKey: ios_username
      remoteRef:
        key: secret/infrastructure/cisco-switch
        property: user
```

**Benefits:**
- ✅ No manual script execution
- ✅ Automatic updates every 5 minutes
- ✅ GitOps-friendly (declarative)
- ✅ Audit trail in Kubernetes events

**Deprecated Scripts:**
- `kubernetes/apps/oxidized/sync-secrets.sh` → Use `external-secret.yaml`
- Manual `kubectl create secret` commands → Use ExternalSecret

## Security Considerations

### What's Protected

✅ **Secrets stay in Vault** - Primary storage
✅ **Kubernetes secrets are ephemeral** - Recreated from Vault
✅ **Audit logging** - Vault tracks all access
✅ **Automatic rotation** - Update Vault, secrets propagate
✅ **Access control** - Vault policies control who reads what

### What's NOT Protected

⚠️ **Kubernetes etcd encryption** - Secrets still stored in etcd (encrypted at rest if enabled)
⚠️ **Pod exec access** - Anyone who can exec into pod can read mounted secrets
⚠️ **Namespace access** - Anyone with get/list secrets in namespace can read

### Best Practices

1. **Enable Kubernetes secrets encryption at rest**
   ```bash
   # Check if enabled
   kubectl get secret -n kube-system | grep encryption-config
   ```

2. **Limit RBAC access to secrets**
   ```yaml
   # Don't grant blanket secrets access
   - apiGroups: [""]
     resources: ["secrets"]
     verbs: ["get", "list"]  # ❌ Too broad
   ```

3. **Use Vault audit logging**
   ```bash
   vault audit enable file file_path=/vault/logs/audit.log
   ```

4. **Rotate Vault tokens periodically**
   ```bash
   # Create token with TTL
   vault token create -policy=external-secrets -ttl=720h
   ```

5. **Monitor ExternalSecret sync failures**
   ```bash
   # Alert on SecretSyncedError
   kubectl get externalsecret --all-namespaces -o json | \
     jq '.items[] | select(.status.conditions[].type == "Ready" and .status.conditions[].status == "False")'
   ```

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Vault KV Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)
