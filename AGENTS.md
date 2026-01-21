# AGENTS.md for opencode

This repository manages Lanmine.no infrastructure. Treat this guidance as instructions for Codex/opencode agents working in this tree.

## Overview

- Infrastructure defined in Terraform under `terraform/`, provisioning Proxmox VMs via the `bpg/proxmox` provider.
- Ansible under `ansible/` handles configuration backups and service deployment, with Vault managing secrets.
- Vault secrets are sourced from `secret/infrastructure/*` paths. Never commit secrets directly.
- This repo has workflows under `.github/workflows/` for Terraform checks, scheduled backups, and Vault deploys.

## Key Workflows

### Terraform
- Load Vault secrets before running Terraform: `cd terraform && source load_tf_secrets.sh`.
- Initialize with PostgreSQL backend: `terraform init -backend-config="conn_str=${PG_CONN_STR}"`.
- Standard workflow: `terraform plan` → `terraform apply`.

### Local Validation
- Run `./test-local.sh` for standard checks.
- Use `./test-local.sh --quick` for syntax-only verification.
- Use `./test-local.sh --full` when you need a comprehensive run (includes Terraform plan).

### Ansible
- Backups and deployments run from `ansible/`. Key playbooks include:
  - `playbooks/backup-all.yml` (runs all backup roles, commits encrypted `.age` artifacts).
  - `playbooks/configure-rsyslog.yml` (sets up rsyslog forwarding on `linux_vms`).
  - `playbooks/deploy-akvorado.yml` (installs Akvorado stack on `akvorado-01`).

## Infrastructure Notes

- Hosts managed include Proxmox, OPNsense, Vault, PostgreSQL, Authentik, Akvorado, and Talos control/worker nodes (see `CLAUDE.md` for IPs and roles).
- Kubernetes cluster runs on Talos with Traefik, MetalLB, cert-manager, Longhorn, and monitoring via kube-prometheus-stack.
- Tailscale and Grafana access is routed through `lionfish-caiman.ts.net` with Authentik OAuth backed by Vault secrets.
- Backups rely on Ansible roles: `opnsense_backup`, `proxmox_backup`, `vault_backup`, `postgres_backup`, `rsyslog_forward`, `akvorado_install`.

## Agent Conduct

- Use `terraform fmt` when editing Terraform and follow snake_case for resources/variables.
- Shell scripts should use `set -euo pipefail` and descriptive error messages.
- Prefer descriptive names and kebab-case file naming.
- Never hardcode secrets: always reference Vault paths.
- Ansible backups store encrypted `.age` files under `ansible/backups/` – keep them up to date.

## Git Expectations

- Keep commits concise and factual; don’t append "Generated with Claude Code" or similar metadata.
- Only commit when explicitly asked; avoid premature commits.

## Additional Context

This guidance mirrors the operational details in `CLAUDE.md` but is tailored for opencode usage. Consult `CLAUDE.md` for more architecture diagrams, flows, and ancillary references when needed.
