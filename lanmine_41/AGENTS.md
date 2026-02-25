# AGENTS.md

Instructions for non-Claude AI agents (Codex, Copilot, Cursor, etc.) working in this repository. For Claude Code, see `CLAUDE.md`.

## Overview

Infrastructure-as-code for Lanmine.no:
- **Terraform** (`terraform/`): Proxmox VMs via `bpg/proxmox` provider, PostgreSQL state backend
- **Ansible** (`ansible/`): Configuration backups, service deployment, secrets from Vault
- **Kubernetes** (`kubernetes/`): Talos Linux cluster with GitOps via ArgoCD

## Quick Reference

### Terraform
```bash
cd terraform && source load_tf_secrets.sh
terraform init -backend-config="conn_str=${PG_CONN_STR}"
terraform plan && terraform apply
```

### Validation
```bash
./test-local.sh           # Standard checks
./test-local.sh --quick   # Syntax only
./test-local.sh --full    # Full test with terraform plan
```

### Ansible
```bash
cd ansible
ansible-playbook playbooks/backup-all.yml        # All backups
ansible-playbook playbooks/deploy-lancache.yml   # LANcache
ansible-playbook playbooks/deploy-n8n.yml        # n8n
ansible-playbook playbooks/deploy-snmp-agents.yml # SNMP monitoring
```

## Infrastructure Hosts

| Host | IP | Purpose |
|------|-----|---------|
| proxmox | 10.0.10.5 | Proxmox VE hypervisor |
| opnsense | 10.0.10.1 | Firewall/gateway |
| vault-01 | 10.0.10.21 | HashiCorp Vault |
| runner-01 | 10.0.10.22 | GitHub Actions runner |
| postgres-01 | 10.0.10.23 | PostgreSQL |
| authentik-01 | 10.0.10.25 | SSO/Identity Provider |
| akvorado-01 | 10.0.10.26 | Network flow collector |
| n8n-01 | 10.0.10.27 | Workflow automation |
| talos-cp-01 | 10.0.10.30 | Kubernetes control plane |
| talos-bdg-qhb | 10.0.10.102 | Kubernetes worker |
| ubuntu-mgmt02 | 10.0.20.2 | LANcache server (VLAN 20) |

## Kubernetes Stack

- **Distribution**: Talos Linux
- **CNI**: Cilium with Hubble
- **Ingress**: Traefik (LoadBalancer: 10.0.10.40)
- **GitOps**: ArgoCD v3.2.5
- **Monitoring**: kube-prometheus-stack
- **Certificates**: cert-manager (internal CA + Let's Encrypt)
- **Storage**: Longhorn + local-path-provisioner
- **Load Balancer**: MetalLB (10.0.10.40-49)

## Network Architecture

| VLAN | Subnet | Purpose |
|------|--------|---------|
| LAN | 10.0.1.0/24 | Management |
| 10 | 10.0.10.0/24 | Infrastructure |
| 20 | 10.0.20.0/23 | Contestants |
| 30 | 10.0.30.0/24 | OOB/iDRAC |
| 99 | 10.0.99.0/24 | Switch management |

## Vault Secrets

All secrets at `secret/infrastructure/*`:
- `proxmox` - API credentials
- `ssh` - SSH keys and usernames
- `postgres` - Database connection strings
- `switches/global` - Switch credentials
- `netbox` - NetBox API token
- `smtp` - Email credentials
- `authentik` - OAuth credentials
- `snmp` - SNMP community strings

## Ansible Roles

| Role | Purpose |
|------|---------|
| `opnsense_backup` | Backup OPNsense, encrypt with age |
| `proxmox_backup` | Backup Proxmox, encrypt with age |
| `vault_backup` | Backup Vault storage |
| `postgres_backup` | PostgreSQL pg_dump |
| `rsyslog_forward` | Forward logs to Loki |
| `akvorado_install` | Akvorado flow collector |
| `lancache_install` | LANcache game cache |
| `n8n_install` | n8n workflow automation |
| `snmp_agent` | Deploy SNMP agents to VMs |

## Code Standards

- **Terraform**: snake_case, `terraform fmt`
- **Shell**: `set -euo pipefail`, descriptive errors
- **Files**: kebab-case naming
- **Secrets**: Always use Vault, never hardcode

## Git Commits

- Keep commits concise and factual
- No "Generated with AI" or co-author metadata
- Only commit when explicitly asked

## External Access

**Tailscale** (`*.lionfish-caiman.ts.net`):
- ArgoCD, Grafana, Alertmanager, Prometheus
- Vault, Akvorado, n8n, Hubble UI
- Uptime Kuma, NetBox, Traefik dashboard

**Cloudflare** (`*.hl0.dev`):
- Public DNS with Let's Encrypt certificates
- Points to Traefik at 10.0.10.40

## Monitoring

- **SNMP**: 9 devices (Linux VMs + switch + firewall)
- **node-exporter**: Kubernetes nodes
- **Uptime Kuma**: 16 HTTP/ICMP monitors
- **Prometheus**: 42 active targets
- **Alerting**: 16 rules with email to tech@lanmine.no

## Related Files

- `CLAUDE.md` - Full documentation for Claude Code
- `docs/` - Architecture docs and implementation plans
- `kubernetes/infrastructure/` - Core K8s components
- `kubernetes/apps/` - Application deployments
