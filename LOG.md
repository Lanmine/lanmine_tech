# Infrastructure Deployment Log

## SECURITY NOTICE
This log contains redacted sensitive information. Never commit actual credentials.

---

## 2025-12-26: Tailscale Operator & Grafana OAuth with Authentik

### Tailscale Kubernetes Operator

Deployed Tailscale Operator for secure remote access to cluster services with automatic Let's Encrypt HTTPS.

**Setup:**
1. Created OAuth client in Tailscale Admin Console with scopes: Auth Keys (Write), Devices (Read/Write)
2. Stored credentials in Vault at `secret/infrastructure/tailscale`
3. Created Kubernetes secret `operator-oauth` in `tailscale` namespace
4. Deployed operator via Flux HelmRelease

**Configuration:**
- Operator hostname: `k8s-operator`
- Default tags: `tag:k8s` (must exist in Tailscale ACL)
- Ingress class: `tailscale`

**Exposed Services:**
| Service | Tailscale URL |
|---------|---------------|
| Grafana | https://grafana.lionfish-caiman.ts.net |
| Traefik | https://traefik.lionfish-caiman.ts.net/dashboard/ |

**Files:**
- `kubernetes/infrastructure/tailscale/` - Operator manifests
- `kubernetes/apps/traefik/traefik-tailscale.yaml` - Traefik Tailscale ingress
- `kubernetes/apps/monitoring/grafana-ingress.yaml` - Grafana Tailscale ingress

### Grafana OAuth with Authentik

Configured Grafana to use Authentik as OAuth provider for SSO.

**Authentik Setup:**
1. Created OAuth2/OpenID Provider named `grafana`
2. Created Application linked to the provider
3. Redirect URI: `https://grafana.lionfish-caiman.ts.net/login/generic_oauth`

**Grafana Configuration:**
- OAuth credentials stored in Vault at `secret/infrastructure/authentik`
- Kubernetes secret `grafana-oauth` in `monitoring` namespace with `client_id` and `client_secret`
- `envFromSecret: grafana-oauth` in Grafana Helm values

**Network Configuration:**
Since Grafana pods can't resolve Tailscale hostnames, OAuth endpoints use:
- `auth_url`: Tailscale URL (browser redirect)
- `token_url`: LAN IP `http://10.0.10.25:9000/application/o/token/`
- `api_url`: LAN IP `http://10.0.10.25:9000/application/o/userinfo/`

**Role Mapping:**
```
contains(groups[*], 'Grafana Admins') && 'Admin' ||
contains(groups[*], 'Grafana Editors') && 'Editor' || 'Viewer'
```

### Traefik Dashboard Fix

Fixed 502 error accessing Traefik dashboard via Tailscale:
1. Changed service port from 9000 to 8080 (correct dashboard port)
2. Enabled `--api.insecure=true` via `additionalArguments` in Helm values

### Grafana Admin Password

Moved Grafana admin password from hardcoded value to Vault:
- Stored in Vault at `secret/infrastructure/grafana`
- Kubernetes secret `grafana-admin` in monitoring namespace
- HelmRelease uses `admin.existingSecret` to reference the secret

---

## 2025-12-21: Authentik VM Deployment Issues

### Authentik VM Configuration Added
- **VMID**: 9125
- **Name**: authentik-01  
- **IP**: 10.0.10.25
- **Specs**: 2 cores, 4GB RAM, 50GB disk
- **Purpose**: Authentik SSO and Identity Provider

### Issues Encountered
1. **Vault Sealed**: GitHub Actions workflow failed due to Vault being sealed
2. **Fix Applied**: Successfully unsealed Vault using provided unseal keys
3. **Missing AppRole**: Created GitHub Actions AppRole and policy in Vault
4. **Secrets Updated**: Updated GitHub repository secrets with correct AppRole credentials
5. **VM Conflict**: Authentik VM already exists in Proxmox but not in Terraform state

### Current Status
- ✅ Vault unsealed and operational
- ✅ GitHub Actions workflow fixed and tested
- ✅ Terraform PostgreSQL backend working
- ✅ Environment variables configured
- ❌ Authentik VM conflict resolution pending
- ❌ VM not properly managed by Terraform

### GitHub Actions Status
- **Workflow**: Fixed and operational
- **Secrets**: Updated with correct AppRole credentials
- **Testing**: Successfully ran plan job
- **Apply**: Pending VM conflict resolution

### Next Steps
1. ✅ Resolve VM 9125 conflict (changed VMID to 9199)
2. 🔄 Authentik VM deployment in progress via GitHub Actions
3. ⏳ Waiting for VM creation to complete
4. Verify VM is accessible and working
5. Configure Authentik installation

---

## 2025-12-19: Terraform Provider Migration

### Migrated from telmate/proxmox to bpg/proxmox

The telmate/proxmox provider v2.9.x required VM.Monitor permission which was removed in Proxmox 9.0. The provider's 3.x branch has issues and is in RC phase.

**Solution**: Migrated to the actively maintained [bpg/proxmox](https://github.com/bpg/terraform-provider-proxmox) provider.

Changes made:
- Updated `main.tf` to use `bpg/proxmox >= 0.70.0`
- Changed resource type from `proxmox_vm_qemu` to `proxmox_virtual_environment_vm`
- Updated provider config to use combined `api_token` format
- Updated `variables.tf` and `tf-run.sh` for new token format
- Updated `outputs.tf` for new resource attributes
- Imported existing VMs into new provider state

Key syntax differences:
```hcl
# telmate (old)
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
}

# bpg (new)
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token  # format: user@realm!tokenid=secret
}
```

**Note**: Runner VM had qemu-guest-agent enabled in Proxmox but no agent installed. Disabled agent to allow import.

---

## 2025-12-18: PostgreSQL Backend & Cloudflare Tunnel

### PostgreSQL for Terraform State
Created LXC container for remote Terraform state storage:

- **Container**: postgres-01 (CTID 9130)
- **IP**: 10.0.10.23
- **Specs**: 1 core, 512MB RAM, 10GB disk
- **Database**: tfstate
- **User**: terraform

Setup steps:
```bash
# Downloaded Ubuntu 24.04 LXC template via Proxmox API
# Created container with static IP on VLAN 10
# Installed PostgreSQL 16
apt-get install -y postgresql postgresql-contrib

# Configured to accept network connections
# /etc/postgresql/16/main/postgresql.conf
listen_addresses = '*'

# /etc/postgresql/16/main/pg_hba.conf
host all all 10.0.10.0/24 scram-sha-256
```

Credentials stored in Vault:
```bash
vault kv put secret/infrastructure/postgres \
  host="10.0.10.23" \
  port="5432" \
  database="tfstate" \
  username="terraform" \
  password="[REDACTED]" \
  connection_string="postgres://terraform:[REDACTED]@10.0.10.23:5432/tfstate?sslmode=disable"
```

### Cloudflare Tunnel
Set up Cloudflare Tunnel for remote access to lab services:

- **Tunnel Name**: lanmine
- **Tunnel ID**: 2087ff2e-6ac8-401c-b693-8237646feec5
- **Domain**: *.tech.lanmine.no (CNAME to tunnel)

**Active Routes:**
- `proxmox.tech.lanmine.no` → Proxmox (100.95.190.77:8006 via Tailscale)
- `opnsense.tech.lanmine.no` → OPNsense (100.110.230.3:443 via Tailscale)
- `vault.tech.lanmine.no` → Vault (100.104.235.24:8200 via Tailscale)

Setup steps:
```bash
# Installed cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o ~/bin/cloudflared
chmod +x ~/bin/cloudflared

# Created systemd user service
# ~/.config/systemd/user/cloudflared.service
# Fetches token from Vault on startup

systemctl --user enable cloudflared
systemctl --user start cloudflared

# Enabled lingering for user services
loginctl enable-linger ubuntu-mgmt01

# Created ingress configuration
# ~/.cloudflared/config.yml
# Routes subdomains to internal services via Tailscale IPs
```

Tunnel token stored in Vault:
```bash
vault kv put secret/infrastructure/cloudflare \
  tunnel_id="2087ff2e-6ac8-401c-b693-8237646feec5" \
  tunnel_token="[REDACTED]" \
  tunnel_name="lanmine"
```

**Testing Access:**
```bash
# DNS resolves correctly (verify with Cloudflare DNS)
dig @1.1.1.1 proxmox.tech.lanmine.no
dig @1.1.1.1 opnsense.tech.lanmine.no
dig @1.1.1.1 vault.tech.lanmine.no

# Test from browser or external device
https://proxmox.tech.lanmine.no
https://opnsense.tech.lanmine.no
https://vault.tech.lanmine.no
```

### Terraform Helper Script
Created `tf-run.sh` to fetch all secrets from Vault before running Terraform:
```bash
#!/bin/bash
# Fetches PG_CONN_STR and TF_VAR_* from Vault
# Usage: ./tf-run.sh plan|apply|destroy
```

### Updated main.tf
- Added PostgreSQL backend configuration
- Using Proxmox provider 2.9.x syntax
- All secrets passed via environment variables from Vault

---

## 2025-12-18: Infrastructure Security Improvements

### Removed Hardcoded Secrets
Eliminated all hardcoded secrets from the codebase:

- **terraform.tfvars**: Deleted - contained Proxmox API credentials in plaintext
- **Action**: All secrets now fetched from Vault at runtime

### GitHub Actions Update
Workflow uses hashicorp/vault-action@v2 to fetch secrets:
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
      secret/data/infrastructure/proxmox api_token_secret | PROXMOX_TOKEN_SECRET ;
      secret/data/infrastructure/ssh public_key | SSH_PUBLIC_KEY
```

---

## 2025-12-17: GitHub Actions Runner VM

### Added runner-01 VM
- **VMID**: 9120
- **IP**: 10.0.10.22
- **Specs**: 4 cores, 8GB RAM, 50GB disk
- **Purpose**: Dedicated GitHub Actions runner

### Post-Deploy Setup
```bash
ssh ubuntu@10.0.10.22

mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.329.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.329.0/actions-runner-linux-x64-2.329.0.tar.gz
tar xzf actions-runner-linux-x64-2.329.0.tar.gz
./config.sh --url https://github.com/Lanmine/lanmine_tech --token [TOKEN]
sudo ./svc.sh install
sudo ./svc.sh start
```

---

## 2025-12-16: Infrastructure Changes

### Removed Kubernetes VMs
Used Proxmox API to remove old test VMs:
- k8s-control-2 (VMID: 9302)
- k8s-worker-1 (VMID: 9311)

### Stored Proxmox Credentials in Vault
```bash
vault kv put secret/infrastructure/proxmox \
  api_url="https://10.0.10.5:8006/api2/json" \
  api_token_id="pxmxapi@pve!ubuntu-mgmt01" \
  api_token_secret="[REDACTED]"
```

---

## Current Infrastructure

| Host | IP | Type | Purpose | Status |
|------|-----|------|---------|--------|
| ubuntu-mgmt01 | 10.0.10.20 | VM | Management | Running |
| vault-01 | 10.0.10.21 | VM | HashiCorp Vault | Running |
| runner-01 | 10.0.10.22 | VM | GitHub Actions Runner | Running |
| postgres-01 | 10.0.10.23 | LXC | PostgreSQL (TF state) | Running |
| authentik-01 | 10.0.10.25 | VM | Authentik SSO | Configured but conflict |

---

## Next Steps

1. ~~Fix Proxmox API token permissions~~ (Resolved by migrating to bpg provider)
2. Configure Cloudflare Tunnel ingress rules in Zero Trust dashboard
3. Set up Vault policies for least-privilege access
4. Install qemu-guest-agent on runner-01 VM
5. ~~Plan Kubernetes deployment (Phase 3 of homelab plan)~~
6. Resolve Authentik VM conflict and complete deployment
7. Configure Authentik installation

---

## 2025-12-19: OPNsense API Access Configured

### Setup OPNsense API Access

Successfully configured API access to OPNsense firewall for automation and certificate deployment.

**Actions taken:**
1. Created dedicated `admin` user in OPNsense web UI
2. Generated API key and secret for `admin` user
3. Stored credentials securely in Vault at `secret/infrastructure/opnsense`
4. Verified API connectivity from ubuntu-mgmt01

**OPNsense Details:**
- **Web UI**: http://10.0.10.1 (LAN), http://100.110.230.3 (Tailscale)
- **SSH**: Port 22 (admin user)
- **API**: HTTP on port 80 (ready for automation)
- **Interfaces**: LAN (igb0), WAN (igb1), vlan10, Tailscale (ts0)

**Vault Secret Structure:**
```bash
vault kv get secret/infrastructure/opnsense
# Fields: api_key, api_secret, web_url, user
```

**Testing:**
```bash
# Test API connectivity
~/bin/test-opnsense-api.sh

# Manual API call example
API_KEY=$(ssh ubuntu@vault-01 'vault kv get -field=api_key secret/infrastructure/opnsense')
API_SECRET=$(ssh ubuntu@vault-01 'vault kv get -field=api_secret secret/infrastructure/opnsense')
curl -s -k -u "$API_KEY:$API_SECRET" http://10.0.10.1/api/diagnostics/system/systemResources
```

**Next Steps:**
- Add SSH public key to `admin` user for passwordless access
- Configure Let's Encrypt certificate deployment via API
- Automate firewall rule management


**SSH Access Configured:**
- ✓ SSH key added to `admin` user
- ✓ Passwordless SSH working from ubuntu-mgmt01
- ✓ Can access OPNsense config and tools
- ✓ Ready for certificate deployment automation

**Test Commands:**
```bash
# SSH access
ssh admin@10.0.10.1

# Via Tailscale
ssh admin@100.110.230.3

# System info via API
~/bin/test-opnsense-api.sh
```