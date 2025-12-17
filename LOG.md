# Infrastructure Deployment Log

## SECURITY NOTICE
This log contains redacted sensitive information. Never commit actual credentials.

---

## 2025-12-16: Infrastructure Changes

### Removed Kubernetes VMs
Used Proxmox API to identify and remove:
- k8s-control-2 (VMID: 9302)
- k8s-worker-1 (VMID: 9311)

API calls:
```bash
curl -s -k https://10.0.10.5:8006/api2/json/nodes/proxmox01/qemu \
  -H "Authorization: PVEAPIToken=pxmxapi@pve!ubuntu-mgmt01=[TOKEN]"

curl -s -k -X POST "https://10.0.10.5:8006/api2/json/nodes/proxmox01/qemu/9302/status/stop" \
  -H "Authorization: PVEAPIToken=pxmxapi@pve!ubuntu-mgmt01=[TOKEN]"

curl -s -k -X DELETE "https://10.0.10.5:8006/api2/json/nodes/proxmox01/qemu/9302" \
  -H "Authorization: PVEAPIToken=pxmxapi@pve!ubuntu-mgmt01=[TOKEN]"
```

Remaining VMs after cleanup:
- vault-01 (VMID: 9110) - Running
- ubuntu01 (VMID: 100) - Running
- talos-template (VMID: 9100) - Stopped
- ubuntu-24.04-template (VMID: 9000) - Stopped

### Stored Proxmox Credentials in Vault
```bash
ssh ubuntu@10.0.10.21
vault kv put secret/infrastructure/proxmox \
  api_url="https://10.0.10.5:8006/api2/json" \
  api_token_id="pxmxapi@pve!ubuntu-mgmt01" \
  api_token_secret="[REDACTED]"
```

### Updated GitHub Workflow
Replaced custom scripts with hashicorp/vault-action@v2:

```yaml
- name: Authenticate and get secrets from Vault
  uses: hashicorp/vault-action@v2
  with:
    url: https://10.0.10.21:8200
    tlsSkipVerify: true
    method: approle
    roleId: ${{ secrets.VAULT_ROLE_ID }}
    secretId: ${{ secrets.VAULT_SECRET_ID }}
    secrets: |
      secret/data/infrastructure/proxmox api_url | PROXMOX_API_URL ;
      secret/data/infrastructure/proxmox api_token_id | PROXMOX_TOKEN_ID ;
      secret/data/infrastructure/proxmox api_token_secret | PROXMOX_TOKEN_SECRET
```

### Required GitHub Secrets
- VAULT_ROLE_ID
- VAULT_SECRET_ID

---

## Current Infrastructure

| VM | IP | Purpose | Status |
|----|-----|---------|--------|
| ubuntu-mgmt01 | 10.0.10.20 | Management & GitHub Runner | Running |
| vault-01 | 10.0.10.21 | HashiCorp Vault | Running |

---

## Next Steps

1. Add VAULT_ROLE_ID and VAULT_SECRET_ID to GitHub secrets
2. Test updated workflow
3. Set up Vault policies for least-privilege access
4. Plan Kubernetes deployment when ready