#!/bin/bash
set -euo pipefail

export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"

SECRET_KEY=$(vault kv get -field=secret_key secret/infrastructure/netbox)
DB_PASSWORD=$(vault kv get -field=db_password secret/infrastructure/netbox)
SUPERUSER_PASSWORD=$(vault kv get -field=superuser_password secret/infrastructure/netbox)
SUPERUSER_API_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)

# Create netbox-postgres secret
kubectl create secret generic netbox-postgres \
  --from-literal=host="10.0.10.23" \
  --from-literal=port="5432" \
  --from-literal=database="netbox" \
  --from-literal=username="netbox" \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=netbox \
  --dry-run=client -o yaml | kubectl apply -f -

# Create netbox-redis secret
kubectl create secret generic netbox-redis \
  --from-literal=host="netbox-redis" \
  --from-literal=port="6379" \
  --from-literal=database="0" \
  --from-literal=cache-database="1" \
  --namespace=netbox \
  --dry-run=client -o yaml | kubectl apply -f -

# Create netbox-secret secret
kubectl create secret generic netbox-secret \
  --from-literal=secret-key="$SECRET_KEY" \
  --namespace=netbox \
  --dry-run=client -o yaml | kubectl apply -f -

# Create netbox-superuser secret
kubectl create secret generic netbox-superuser \
  --from-literal=username="admin" \
  --from-literal=email="admin@lanmine.no" \
  --from-literal=password="$SUPERUSER_PASSWORD" \
  --from-literal=api-token="$SUPERUSER_API_TOKEN" \
  --namespace=netbox \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets synced from Vault to netbox namespace"
