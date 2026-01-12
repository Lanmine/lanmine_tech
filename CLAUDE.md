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
| `lancache_install` | Install LANcache game download cache via Docker |
| `n8n_install` | Install n8n workflow automation via Docker |

**Playbooks:**
| Playbook | Purpose |
|----------|---------|
| `backup-all.yml` | Run all backup roles, commit to git |
| `configure-rsyslog.yml` | Configure syslog forwarding on linux_vms |
| `deploy-akvorado.yml` | Install and configure Akvorado |
| `deploy-lancache.yml` | Install and configure LANcache |
| `deploy-n8n.yml` | Install and configure n8n |
| `deploy-n8n-workflows.yml` | Deploy n8n workflows from JSON files |

**Host Groups:**
- `infrastructure` - All infrastructure hosts
- `linux_vms` - Linux VMs with rsyslog (vault, runner, authentik, postgres, akvorado, n8n)
- `n8n_servers` - n8n workflow automation servers
- `lancache_servers` - LANcache servers (ubuntu-mgmt02)

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
| n8n-01 | 10.0.10.27 | n8n workflow automation |
| talos-cp-01 | 10.0.10.30 | Talos Kubernetes control plane |
| talos-worker-01 | 10.0.10.31 | Talos Kubernetes worker |
| talos-worker-02 | 10.0.10.32 | Talos Kubernetes worker |
| ubuntu-mgmt02 | 10.0.20.2 | LANcache server (Dell R630, VLAN 20) |

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
| n8n | https://n8n.lionfish-caiman.ts.net |
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

## LANcache (Game Download Cache)

LANcache runs on a physical server (`ubuntu-mgmt02`, 10.0.20.2) on VLAN 20 with LAN contestants, caching game downloads from Steam, Origin, Epic, etc.

**Architecture:**
- **lancache-dns**: Intercepts CDN domain queries, returns LANcache IP
- **lancache-monolithic**: Caches HTTP game downloads, proxies HTTPS

**Ports:**
| Port | Protocol |
|------|----------|
| 53/udp | DNS (lancache-dns) |
| 80/tcp | HTTP cache |
| 443/tcp | HTTPS passthrough (SNI proxy) |

**Configuration:**
- Ansible role: `ansible/roles/lancache_install/`
- Docker Compose stack at `/opt/lancache/` on the server
- Cache storage at `/cache/`
- Vault secrets at `secret/infrastructure/lancache`

**Deployment:**
```bash
cd ansible && ansible-playbook playbooks/deploy-lancache.yml
```

## n8n (Workflow Automation)

n8n runs on a dedicated VM (`n8n-01`, 10.0.10.27) providing AI-powered workflow automation with Azure OpenAI integration.

**Architecture:**
- **n8n**: Workflow engine with queue mode
- **PostgreSQL**: Workflow and execution storage
- **Redis**: Job queue for worker scaling

**Ports:**
| Port | Protocol |
|------|----------|
| 5678/tcp | Web UI and API |

**Configuration:**
- Ansible role: `ansible/roles/n8n_install/`
- Docker Compose stack at `/opt/n8n/` on the VM
- Vault secrets at `secret/infrastructure/n8n`

**Code-First Workflow Management:**
- Workflows stored as JSON in `ansible/files/n8n-workflows/`
- Claude generates workflow JSON from natural language descriptions
- Deploy via: `ansible-playbook playbooks/deploy-n8n-workflows.yml`

**Deployment:**
```bash
# Deploy n8n service
cd ansible && ansible-playbook playbooks/deploy-n8n.yml

# Deploy workflows from JSON files
ansible-playbook playbooks/deploy-n8n-workflows.yml
```

**Tailscale Access:** https://n8n.lionfish-caiman.ts.net

## Network Architecture

**VLANs:**
| VLAN | Subnet | Purpose | Gateway |
|------|--------|---------|---------|
| LAN | 10.0.1.0/24 | Management LAN | 10.0.1.1 |
| 10 | 10.0.10.0/24 | Infrastructure | 10.0.10.1 |
| 20 | 10.0.20.0/23 | Contestants | 10.0.20.1 |
| 30 | 10.0.30.0/24 | OOB/iDRAC | 10.0.30.1 |

**Core Network (planned):**
- 2 × Nexus switches in vPC domain
- LANcache: 2 × 10G LACP bond (20 Gbps aggregate)
- HSRP for gateway redundancy
- Edge switches: 10G uplinks, 1G to clients

**LANcache Bonding (802.3ad LACP):**
```yaml
# /etc/netplan/01-lancache.yaml - bond config
bonds:
  bond0:
    interfaces: [eno49, eno50]
    parameters:
      mode: 802.3ad
      lacp-rate: fast
      transmit-hash-policy: layer3+4
```

## DHCP (Kea)

OPNsense runs Kea DHCP for all networks (dnsmasq disabled).

| Network | Pool | DNS | Description |
|---------|------|-----|-------------|
| LAN | 10.0.1.3-254 | 10.0.1.1 | Management |
| VLAN 10 | 10.0.10.100-110 | 10.0.10.1 | Infrastructure |
| VLAN 20 | 10.0.20.5-21.254 | 10.0.20.2 (LANcache) | Contestants |

- Kea API: `https://10.0.10.1/api/kea/dhcpv4/`

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
