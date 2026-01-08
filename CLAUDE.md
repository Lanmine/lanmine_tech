# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is infrastructure-as-code for Lanmine.no, managing Proxmox VE virtual machines via Terraform, with Ansible for configuration backups. Secrets are managed through HashiCorp Vault.

## Token Conservation

Be conservative with token usage:
- Keep responses concise and to the point
- Avoid verbose explanations unless asked
- Use tables and bullet points over paragraphs
- Don't repeat information already shown in tool output
- Skip unnecessary confirmations and preamble
- Prefer targeted file reads over reading entire files when possible

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

**Roles:**
| Role | Purpose |
|------|---------|
| `opnsense_backup` | Backup OPNsense config, encrypt with age |
| `proxmox_backup` | Backup Proxmox config, encrypt with age |
| `vault_backup` | Vault file storage backup, encrypt with age |
| `postgres_backup` | PostgreSQL pg_dump, encrypt with age |
| `rsyslog_forward` | Configure rsyslog to forward logs to Loki |
| `akvorado_install` | Install Akvorado flow collector via Docker |

**Playbooks:**
| Playbook | Purpose |
|----------|---------|
| `backup-all.yml` | Run all backup roles, commit to git |
| `configure-rsyslog.yml` | Configure syslog forwarding on linux_vms |
| `deploy-akvorado.yml` | Install and configure Akvorado |

**Host Groups:**
- `infrastructure` - All infrastructure hosts
- `linux_vms` - Linux VMs with rsyslog (vault, runner, authentik, postgres)

**Secrets**:
- Vault integration via `group_vars/all/vault.yml`
- SSH usernames stored in Vault at `secret/infrastructure/ssh`
- Backups stored in `ansible/backups/`, encrypted `.age` files committed to git

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
| vault-01 | 10.0.10.21 | HashiCorp Vault (file storage backend) |
| runner-01 | 10.0.10.22 | GitHub Actions self-hosted runner |
| postgres-01 | 10.0.10.23 | PostgreSQL (Terraform state backend) |
| authentik-01 | 10.0.10.25 | Authentik SSO and Identity Provider |
| akvorado-01 | 10.0.10.26 | Akvorado network flow collector |
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
- **Storage**: Longhorn (distributed, replicated), local-path-provisioner (fallback)
- **Remote Access**: Tailscale Operator with Let's Encrypt HTTPS

### Tailscale Services

| Service | URL |
|---------|-----|
| Glance | https://glance.lionfish-caiman.ts.net |
| Grafana | https://grafana.lionfish-caiman.ts.net |
| Alertmanager | https://alertmanager.lionfish-caiman.ts.net |
| Akvorado | https://akvorado.lionfish-caiman.ts.net |
| Traefik | https://traefik.lionfish-caiman.ts.net/dashboard/ |

### Grafana Authentication

Grafana uses Authentik OAuth for SSO. Configuration:
- OAuth credentials stored in Vault at `secret/infrastructure/authentik`
- Kubernetes secret `grafana-oauth` in monitoring namespace
- Browser redirects go to Tailscale URL, server-side calls use LAN IP (10.0.10.25:9000)

## Akvorado (Network Flow Collector)

Akvorado runs on a dedicated VM (`akvorado-01`, 10.0.10.26) outside the Kubernetes cluster, collecting NetFlow data from OPNsense.

**Architecture:**
- **Inlet**: Receives NetFlow/IPFIX/sFlow UDP packets, sends raw flows to Kafka
- **Outlet**: Decodes flows, enriches with metadata, writes to ClickHouse
- **Console**: Web UI for visualization
- **ClickHouse**: Time-series database for flow storage
- **Kafka + Zookeeper**: Message queue between inlet and outlet

**Flow Collection Ports:**
| Port | Protocol |
|------|----------|
| 2055/udp | NetFlow v5/v9 |
| 4739/udp | IPFIX |
| 6343/udp | sFlow |

**Configuration:**
- Ansible role: `ansible/roles/akvorado_install/`
- Docker Compose stack at `/opt/akvorado/` on the VM
- Interface mappings defined in `defaults/main.yml` (required for metadata enrichment)
- OPNsense exports NetFlow v9 to 10.0.10.26:2055

**Tailscale Access:** https://akvorado.lionfish-caiman.ts.net

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
