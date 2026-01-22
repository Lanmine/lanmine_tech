#!/bin/bash
set -euo pipefail

# Sync Oxidized secrets from Vault to Kubernetes
# Requires: VAULT_ADDR environment variable, vault CLI authenticated

export VAULT_ADDR="${VAULT_ADDR:-https://vault-01.lionfish-caiman.ts.net:8200}"

echo "Fetching secrets from Vault..."

# Get NetBox API token for device discovery
NETBOX_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)

# Get switch credentials
# Username is 'ansible' (created during ZTP bootstrap)
IOS_USERNAME="ansible"
IOS_PASSWORD=$(vault kv get -field=ansible_password secret/infrastructure/switches/global)
IOS_ENABLE_PASSWORD=$(vault kv get -field=enable_secret secret/infrastructure/switches/global)

# NXOS uses same credentials as IOS for now
NXOS_USERNAME="$IOS_USERNAME"
NXOS_PASSWORD="$IOS_PASSWORD"

# Generate random password for Oxidized web UI (or retrieve from Vault if it exists)
if vault kv get secret/infrastructure/oxidized >/dev/null 2>&1; then
  echo "Using existing Oxidized secrets from Vault"
  OXIDIZED_PASSWORD=$(vault kv get -field=web_password secret/infrastructure/oxidized)
else
  echo "Generating new Oxidized web password"
  OXIDIZED_PASSWORD=$(openssl rand -base64 32)
  vault kv put secret/infrastructure/oxidized \
    web_password="$OXIDIZED_PASSWORD"
fi

echo "Creating Kubernetes secret..."

kubectl create secret generic oxidized-secrets \
  --from-literal=netbox_token="$NETBOX_TOKEN" \
  --from-literal=oxidized_password="$OXIDIZED_PASSWORD" \
  --from-literal=ios_username="$IOS_USERNAME" \
  --from-literal=ios_password="$IOS_PASSWORD" \
  --from-literal=ios_enable_password="$IOS_ENABLE_PASSWORD" \
  --from-literal=nxos_username="$NXOS_USERNAME" \
  --from-literal=nxos_password="$NXOS_PASSWORD" \
  --namespace=oxidized \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Oxidized secrets synced successfully"
echo ""
echo "Web UI password: $OXIDIZED_PASSWORD"
echo "(Stored in Vault at secret/infrastructure/oxidized)"
