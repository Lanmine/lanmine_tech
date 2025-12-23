#!/usr/bin/env bash
set -euo pipefail

# Load Terraform variables from Vault
# Source this script before running terraform commands

export VAULT_SKIP_VERIFY=1

export TF_VAR_proxmox_api_url="$(vault kv get -field=api_url secret/infrastructure/proxmox)"
export TF_VAR_ssh_public_key="$(vault kv get -field=public_key secret/infrastructure/ssh)"

TOKEN_ID="$(vault kv get -field=api_token_id secret/infrastructure/proxmox)"
TOKEN_SECRET="$(vault kv get -field=api_token_secret secret/infrastructure/proxmox)"
export TF_VAR_proxmox_api_token="${TOKEN_ID}=${TOKEN_SECRET}"

echo "✔ Terraform environment variables loaded from Vault"
echo "  Proxmox API URL: ${TF_VAR_proxmox_api_url}"
