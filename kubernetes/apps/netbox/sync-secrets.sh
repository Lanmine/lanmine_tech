#!/bin/bash
set -euo pipefail

export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"

SECRET_KEY=$(vault kv get -field=secret_key secret/infrastructure/netbox)
DB_PASSWORD=$(vault kv get -field=db_password secret/infrastructure/netbox)
SUPERUSER_PASSWORD=$(vault kv get -field=superuser_password secret/infrastructure/netbox)
SUPERUSER_API_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)

kubectl create secret generic netbox-secrets \
  --from-literal=secret_key="$SECRET_KEY" \
  --from-literal=db_password="$DB_PASSWORD" \
  --from-literal=superuser_password="$SUPERUSER_PASSWORD" \
  --from-literal=superuser_api_token="$SUPERUSER_API_TOKEN" \
  --namespace=netbox \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets synced from Vault to netbox namespace"
