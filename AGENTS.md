# AGENTS.md

This file provides guidance to AI coding agents (Claude, OpenCode, etc.) when working with code in this repository.

## Project Overview

Infrastructure as Code for a homelab environment running on Proxmox VE. Uses Terraform with PostgreSQL backend for state storage, HashiCorp Vault for secrets management, and Cloudflare Tunnel for remote access.

**Purpose**: Homelab infrastructure management using modern DevOps practices
**Location**: `/home/ubuntu-mgmt01/infra/lanmine_tech`
**Current Focus**: Ansible automation and encrypted backups

## Architecture

- **Hypervisor**: Proxmox VE 9.x at 10.0.10.5
- **Terraform Provider**: `bpg/proxmox` (not telmate - telmate is incompatible with Proxmox 9)
- **State Backend**: PostgreSQL on postgres-01 (10.0.10.23)
- **Secrets**: All secrets stored in HashiCorp Vault on vault-01 (10.0.10.21)
- **CI/CD**: Self-hosted GitHub Actions runner on runner-01 (10.0.10.22)
- **Network**: VLAN 10 (10.0.10.0/24) for infrastructure

### Key Infrastructure VMs
- **ubuntu-mgmt01** (10.0.10.20) - Management workstation
- **vault-01** (10.0.10.21) - HashiCorp Vault server
- **runner-01** (10.0.10.22) - GitHub Actions runner
- **postgres-01** (10.0.10.23) - PostgreSQL for Terraform state

### Vault Secret Paths

```
secret/infrastructure/proxmox    # api_url, api_token_id, api_token_secret
secret/infrastructure/postgres   # connection_string for TF state
secret/infrastructure/ssh        # public_key for VM provisioning
secret/infrastructure/cloudflare # tunnel_token
```

## CI/CD Workflow

Terraform is managed via GitHub Actions (`.github/workflows/vault-deploy.yml`):

- **Pull Request**: Runs `terraform plan`, posts output as PR comment
- **Merge to main**: Runs `terraform apply -auto-approve`
- **Manual**: Can trigger via workflow_dispatch

The workflow runs on self-hosted runner (runner-01) and fetches all secrets from Vault using AppRole authentication.

### Manual Testing

For local testing, you can run terraform directly on ubuntu-mgmt01:

```bash
cd terraform

# Export secrets from Vault
export PG_CONN_STR=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=connection_string secret/infrastructure/postgres')
export TF_VAR_proxmox_api_url=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=api_url secret/infrastructure/proxmox')
TOKEN_ID=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=api_token_id secret/infrastructure/proxmox')
TOKEN_SECRET=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=api_token_secret secret/infrastructure/proxmox')
export TF_VAR_proxmox_api_token="${TOKEN_ID}=${TOKEN_SECRET}"
export TF_VAR_ssh_public_key=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=public_key secret/infrastructure/ssh')

# Run terraform
terraform init
terraform plan
```

## Key Conventions

- VMs use cloud-init with Ubuntu 24.04 templates
- VM IDs: 91xx range (vault=9110, runner=9120)
- LXC IDs: 91xx range (postgres=9130)
- All VMs get static IPs on VLAN 10
- The `bpg/proxmox` provider uses `proxmox_virtual_environment_vm` resource type
- API token format for bpg provider: `user@realm!tokenid=secret`

## Code Style Guidelines

- **Language**: Primarily HCL (Terraform), shell scripting, and YAML configurations
- **Formatting**: Follow Terraform and system conventions
- **Types**: Strong typing where applicable (YAML, JSON configs)
- **Naming**: 
  - Files: kebab-case
  - Variables: snake_case
  - Terraform resources: snake_case
- **Error handling**: Use proper exit codes and error messages
- **Security**: Validate inputs, use secure practices for SSH/keys
- **Documentation**: Include comments for complex configurations

## Documentation Preferences

- **Centralized Documentation**: All project documentation should be gathered in a single `README.md` file
- **No Script Generation**: Do not create scripts without explicit discussion. Talk through each command individually before execution
- **Command-by-Command Approach**: Present commands one at a time, explain what they do, and wait for confirmation before proceeding

## Build/Commands

- **System**: Linux-based management environment (ubuntu-mgmt01)
- **Package managers**: npm, apt available via system
- **Tools**: kubectl, talosctl, sops, age, cloudflared, terraform, vault
- **Testing**: No specific test framework configured
- **Linting**: Standard system linting tools available

## Project Structure

```
/home/ubuntu-mgmt01/
├── infra/lanmine_tech/          # This project
│   ├── .github/workflows/       # GitHub Actions CI/CD
│   ├── terraform/               # Terraform configuration
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── AGENTS.md               # This file
│   ├── LOG.md                  # Deployment history
│   └── README.md
├── .ssh/                        # SSH key management
├── .config/                     # Tool configurations
└── .kube/                       # Kubernetes configs
```

## Important Notes

- Terraform state is remote (PostgreSQL), not local
- GitHub Actions uses Vault AppRole for authentication (secrets: `VAULT_ROLE_ID`, `VAULT_SECRET_ID`)
- See `LOG.md` for detailed deployment history and troubleshooting notes
- Uses OpenCode with local UiO GPT provider (localhost:11435)
- MCP filesystem server enabled for full directory access
- SSH key management in .ssh/ directory
- Ansible installed on runner-01 for configuration management
- All secrets managed through HashiCorp Vault

## Special Configuration

- **AI Tools**: OpenCode, Claude configured
- **MCP Server**: Filesystem server enabled for full directory access
- **Root Directory**: /home/ubuntu-mgmt01
