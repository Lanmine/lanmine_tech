#!/bin/bash
set -euo pipefail

# Sync SNMP exporter secrets from Vault to Kubernetes
# Requires: VAULT_ADDR environment variable, vault CLI authenticated

export VAULT_ADDR="${VAULT_ADDR:-https://vault-01.lionfish-caiman.ts.net:8200}"

echo "Fetching SNMP credentials from Vault..."

# Get SNMP v3 credentials
SNMP_AUTH_PASS=$(vault kv get -field=snmp_v3_auth_pass secret/infrastructure/switches/global)
SNMP_PRIV_PASS=$(vault kv get -field=snmp_v3_priv_pass secret/infrastructure/switches/global)

echo "Creating Kubernetes secret..."

kubectl create secret generic snmp-exporter-secrets \
  --from-literal=snmp_auth_pass="$SNMP_AUTH_PASS" \
  --from-literal=snmp_priv_pass="$SNMP_PRIV_PASS" \
  --namespace=snmp-exporter \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ SNMP exporter secrets synced successfully"
