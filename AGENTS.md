# AGENTS.md

This file provides essential guidance for automated coding agents operating in this repository. Treat it as the canonical summary of the workflow, and keep it aligned with the detailed guidance captured in `CLAUDE.md` (loads of extra context lives there).

## Quick Commands

- `cd terraform && source load_tf_secrets.sh` to bring Vault-provided credentials into the environment before any Terraform work.
- Run `terraform init -backend-config="conn_str=${PG_CONN_STR}"`, followed by `terraform plan` and `terraform apply` for standard Terraform edits.
- Use `./test-local.sh`, optionally with `--quick` for syntax-only checks or `--full` to include `terraform plan`, as a local pre-commit validation step.
- For Ansible backups run `cd ansible` and `ansible-playbook playbooks/backup-all.yml`.

## Build/Lint/Test Commands

- System environment: Linux (ubuntu-mgmt01)
- Package managers: npm, apt
- Tools available: terraform, vault, kubectl, talosctl, sops, age, cloudflared
- Running Terraform commands:
  - `terraform init`, `terraform plan`, `terraform apply`
- Single test execution: No dedicated test framework; execute scripts such as `npm test <testname>` or other repository-specific tooling when introduced.

## Code Style Guidelines

- Language: HCL (Terraform), Bash shell scripts, YAML configs
- Formatting: Follow Terraform and system conventions strictly; use `terraform fmt` when touching HCL
- Imports: Use explicit, minimal imports for scripts
- Types: Use strong typing where applicable (Terraform variables, YAML, JSON)
- Naming:
  - Files: kebab-case
  - Variables: snake_case
  - Terraform resources: snake_case
- Error handling: Provide proper exit codes and descriptive errors
- Security: Validate inputs and never hardcode secrets; Vault is the primary secret manager
- Documentation: Comment complex config and automation thoroughly

## Documentation & Workflow

- Centralize documentation in `README.md`
- Avoid auto-generating scripts; clarify each command before execution
- Prefer stepwise command usage over bulk scripts to maintain clarity

## Architecture Overview

### Terraform (`terraform/`)

- Provider: `bpg/proxmox ~> 0.75` targeting Proxmox VE 9.x
- Backend: PostgreSQL (connection string from Vault at `secret/infrastructure/postgres`)
- VM inventory: Defined in `main.tf` `locals.vms` map with `for_each`; single source of truth for all VMs
- Current VMs: vault-01 (9110), runner-01 (9120), authentik-01 (9199)
- State protection: All VMs use `prevent_destroy = true` and ignore cloud-init drift
- Secrets loaded via `load_tf_secrets.sh`:
  - `secret/infrastructure/proxmox` for API credentials
  - `secret/infrastructure/ssh` for SSH public key used in cloud-init

### Ansible (`ansible/`)

- Roles: `opnsense_backup` and `proxmox_backup`, with configs encrypted via `age`
- Backups: Stored under `ansible/backups/` as encrypted `.age` files committed to git
- Secrets: Integrated through `group_vars/all/vault.yml`

### GitHub Actions (`.github/workflows/`)

- `terraform-check.yml`: Runs PR validation with plan output posted as a comment
- `infrastructure-backup.yml`: Scheduled backups of infrastructure config
- `vault-deploy.yml`: Automates Vault deployment steps
- Workflows authenticate to Vault via AppRole using repo secrets `VAULT_ADDR`, `VAULT_ROLE_ID`, and `VAULT_SECRET_ID`

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

- **Distribution**: Talos Linux (immutable, API-driven)
- **Config**: `talos/` directory contains talosconfig, kubeconfig, and machine configs
- **GitOps**: Flux CD (`kubernetes/` directory)
- **Ingress**: Traefik (LoadBalancer IP: 10.0.10.40)
- **Monitoring**: kube-prometheus-stack (Grafana at https://grafana.lionfish-caiman.ts.net)
- **Dashboard**: Glance (https://glance.lionfish-caiman.ts.net)
- **Remote Access**: Tailscale Operator with automatic Let's Encrypt HTTPS

### Key Commands

```bash
# Talos cluster management
export TALOSCONFIG=/home/ubuntu-mgmt01/infra/lanmine_tech/talos/talosconfig
talosctl health
talosctl dashboard

# Kubernetes access
export KUBECONFIG=/home/ubuntu-mgmt01/infra/lanmine_tech/talos/kubeconfig
kubectl get nodes
kubectl get pods -A

# Flux GitOps
flux reconcile source git flux-system
flux reconcile kustomization apps
flux reconcile kustomization infrastructure
```

### Vault Secrets for Kubernetes

| Path | Purpose |
|------|---------|
| `secret/infrastructure/tailscale` | Tailscale OAuth credentials |
| `secret/infrastructure/authentik` | Grafana OAuth client credentials |
| `secret/infrastructure/grafana` | Grafana admin password |

## MCP Servers

| Server | Purpose |
|--------|---------|
| `postgres` | Query Terraform state backend directly |
| `github-server` | GitHub API operations (issues, PRs, repos) |
| `vault` | HashiCorp Vault secret access |
| `proxmox` | Proxmox VE management (55 tools for VMs, containers, storage) |

### MCP binaries

- Vault: `~/vault-mcp-server/vault-mcp-server`
- Proxmox: `~/mcp-proxmox/index.js` (Node.js from gilby125/mcp-proxmox)

## Additional Notes

- Vault is the primary secret manager; avoid hardcoding secrets
- Terraform provider: `bpg/proxmox` for Proxmox VE 9.x
- Import existing VMs via `terraform import` and validate with `terraform plan`

This file helps maintain uniformity, security, and clarity for AI agents working in this repo.