# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is infrastructure-as-code for Lanmine.no, managing Proxmox VE virtual machines via Terraform, with Ansible for configuration backups. Secrets are managed through HashiCorp Vault.

## Key Commands

### Terraform

```bash
# Load secrets from Vault into environment
cd terraform && source load_tf_secrets.sh

# Initialize with PostgreSQL backend (state stored in Vault-managed PG)
terraform init -backend-config="conn_str=${PG_CONN_STR}"

# Standard workflow
terraform plan
terraform apply
```

### Pre-commit Validation

```bash
# Run local validation before pushing (avoids CI failures)
./test-local.sh           # Standard checks
./test-local.sh --quick   # Syntax only
./test-local.sh --full    # Full test including terraform plan
```

### Ansible Backups

```bash
cd ansible
ansible-playbook playbooks/backup-all.yml
```

## Architecture

### Terraform (`terraform/`)

- **Provider**: bpg/proxmox for Proxmox VE
- **Backend**: PostgreSQL (connection string from Vault at `secret/infrastructure/postgres`)
- **VM inventory**: Defined in `main.tf` `locals.vms` map - single source of truth for all VMs
- **State protection**: All VMs have `prevent_destroy = true` and ignore cloud-init drift

Secrets loaded via `load_tf_secrets.sh`:
- `secret/infrastructure/proxmox` - API credentials
- `secret/infrastructure/ssh` - SSH public key for cloud-init

### Ansible (`ansible/`)

- **Roles**: `opnsense_backup`, `proxmox_backup` - encrypt configs with age
- **Backups**: Stored in `ansible/backups/`, encrypted `.age` files committed to git
- **Secrets**: Vault integration via `group_vars/all/vault.yml`

### GitHub Actions (`.github/workflows/`)

- `terraform-check.yml` - PR validation with plan output as comment
- `infrastructure-backup.yml` - Scheduled backups
- `vault-deploy.yml` - Vault deployment automation

All workflows authenticate to Vault via AppRole using repository secrets: `VAULT_ADDR`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`.

## Infrastructure Hosts

| Host | IP | Purpose |
|------|-----|---------|
| proxmox | 10.0.10.5 | Proxmox VE hypervisor |
| opnsense | 10.0.10.1 | Firewall/gateway |
| vault-01 | 10.0.10.21 | HashiCorp Vault |
| runner-01 | 10.0.10.22 | GitHub Actions self-hosted runner |
| postgres-01 | 10.0.10.23 | PostgreSQL (Terraform state backend) |
| authentik-01 | 10.0.10.25 | Authentik SSO and Identity Provider |
| talos-cp-01 | 10.0.10.30 | Talos Kubernetes control plane |
| talos-worker-01 | 10.0.10.31 | Talos Kubernetes worker |
| talos-worker-02 | 10.0.10.32 | Talos Kubernetes worker |

## Kubernetes Cluster

- **Distribution**: Talos Linux
- **Ingress**: Traefik (LoadBalancer IP: 10.0.10.40)
- **GitOps**: Flux CD
- **Monitoring**: kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
- **Certificates**: cert-manager with internal CA (lanmine-ca-issuer)
- **Load Balancer**: MetalLB (IP range: 10.0.10.40-10.0.10.49)
- **Storage**: local-path-provisioner
- **Remote Access**: Tailscale Operator with Let's Encrypt HTTPS

### Tailscale Services

| Service | URL |
|---------|-----|
| Glance | https://glance.lionfish-caiman.ts.net |
| Grafana | https://grafana.lionfish-caiman.ts.net |
| Traefik | https://traefik.lionfish-caiman.ts.net/dashboard/ |

### Grafana Authentication

Grafana uses Authentik OAuth for SSO. Configuration:
- OAuth credentials stored in Vault at `secret/infrastructure/authentik`
- Kubernetes secret `grafana-oauth` in monitoring namespace
- Browser redirects go to Tailscale URL, server-side calls use LAN IP (10.0.10.25:9000)

## MCP Servers

Claude Code has access to these MCP servers for this repository:

| Server | Purpose |
|--------|---------|
| `postgres` | Query Terraform state backend directly |
| `github-server` | GitHub API operations (issues, PRs, repos) |
| `vault` | HashiCorp Vault secret access |
| `proxmox` | Proxmox VE management (55 tools for VMs, containers, storage) |

MCP binaries:
- Vault: `~/vault-mcp-server/vault-mcp-server`
- Proxmox: `~/mcp-proxmox/index.js` (Node.js, from gilby125/mcp-proxmox)

## Code Style

- Terraform: snake_case for resources/variables, format with `terraform fmt`
- Shell scripts: Use `set -euo pipefail`, descriptive error messages
- File naming: kebab-case
- Never hardcode secrets; always use Vault

## Git Commits

- Do NOT add "Generated with Claude Code" or "Co-Authored-By: Claude" to commit messages
- Keep commit messages concise and descriptive
