# Lanmine Tech Infrastructure

Infrastructure as Code for the Lanmine Tech homelab environment.

## Current Status

| VM | IP | Purpose | VMID | Status |
|----|-----|---------|------|--------|
| ubuntu-mgmt01 | 10.0.10.20 | Management VM | - | Running |
| vault-01 | 10.0.10.21 | HashiCorp Vault | 9110 | Running |

## Architecture

```
                    ┌─────────────────┐
                    │    OPNsense     │
                    │   10.0.10.1     │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │    VLAN 10      │
                    │   10.0.10.0/24  │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────┴───────┐   ┌───────┴───────┐   ┌───────┴───────┐
│  ubuntu-mgmt01 │   │   vault-01    │   │  (future VMs) │
│  10.0.10.20   │   │  10.0.10.21   │   │               │
└───────────────┘   └───────────────┘   └───────────────┘
```

## Stack

- **Hypervisor**: Proxmox VE
- **IaC**: Terraform (telmate/proxmox provider)
- **Secrets**: HashiCorp Vault
- **OS Template**: Ubuntu 24.04 (cloud-init)

## Quick Start

```bash
cd terraform

# Deploy infrastructure
terraform init
terraform plan
terraform apply
```

## Vault Access

```bash
# SSH to Vault
ssh ubuntu@10.0.10.21

# Set environment
export VAULT_ADDR='https://127.0.0.1:8200'
export VAULT_SKIP_VERIFY=true

# Login (userpass)
vault login -method=userpass username=admin

# Read a secret
vault kv get secret/infrastructure/proxmox
```

## Network Plan

### Static IPs (Infrastructure)

| IP | Hostname | Purpose |
|----|----------|---------|
| 10.0.10.1 | gateway | OPNsense router |
| 10.0.10.20 | ubuntu-mgmt01 | Management VM |
| 10.0.10.21 | vault-01 | HashiCorp Vault |
| 10.0.10.22 | runner-01 | GitHub Actions Runner (planned) |
| 10.0.10.31-33 | k8s-cp-* | Kubernetes control planes (planned) |
| 10.0.10.41-43 | k8s-worker-* | Kubernetes workers (planned) |

### Reserved Ranges

| Range | Purpose |
|-------|---------|
| 10.0.10.1-99 | Static infrastructure |
| 10.0.10.100-199 | DHCP (currently disabled) |
| 10.0.10.200-254 | Future expansion |

## Secrets in Vault

```
secret/
├── infrastructure/
│   ├── proxmox       # API credentials (api_url, api_token_id, api_token_secret)
│   ├── ssh           # SSH keypair (private_key, public_key)
│   └── vault         # Unseal keys & root token (backup)
└── cicd/
    └── github-runner # AppRole credentials (role_id, secret_id)
```

## Roadmap

- [x] Vault VM deployment
- [x] Vault initialization & configuration
- [ ] GitHub runner VM (runner-01)
- [ ] Talos Kubernetes cluster
- [ ] CI/CD integration with Vault

## Directory Structure

```
lanmine_tech/
├── .github/          # GitHub Actions workflows
├── terraform/        # Infrastructure definitions
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── outputs.tf
│   └── log.md        # Deployment log
├── .gitignore
├── LICENSE
└── README.md
```

## License

MIT
