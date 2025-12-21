#!/bin/bash

# Fetch secrets from Vault and set environment variables
export PG_CONN_STR=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=connection_string secret/infrastructure/postgres')
export TF_VAR_proxmox_api_url=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=api_url secret/infrastructure/proxmox')
export TF_VAR_ssh_public_key=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=public_key secret/infrastructure/ssh')

TOKEN_ID=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=api_token_id secret/infrastructure/proxmox')
TOKEN_SECRET=$(ssh ubuntu@vault-01 'export VAULT_SKIP_VERIFY=1 && vault kv get -field=api_token_secret secret/infrastructure/proxmox')
export TF_VAR_proxmox_api_token="${TOKEN_ID}=${TOKEN_SECRET}"

echo "Environment variables set:"
echo "PG_CONN_STR: ${PG_CONN_STR:0:20}..."
echo "TF_VAR_proxmox_api_url: $TF_VAR_proxmox_api_url"
echo "TF_VAR_proxmox_api_token: ${TF_VAR_proxmox_api_token:0:20}..."
echo "TF_VAR_ssh_public_key: ${TF_VAR_ssh_public_key:0:20}..."