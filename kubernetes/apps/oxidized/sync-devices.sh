#!/bin/sh
# Sync devices from NetBox to Oxidized router.db
set -e

NETBOX_URL="${NETBOX_URL:-http://netbox.netbox.svc.cluster.local:8080}"
NETBOX_TOKEN="${NETBOX_TOKEN}"
ROUTER_DB="/home/oxidized/.config/oxidized/router.db"

# Fetch devices from NetBox and convert to CSV format
# Format: name:model:ip
curl -s -H "Authorization: Token ${NETBOX_TOKEN}" \
  "${NETBOX_URL}/api/dcim/devices/?status=active&has_primary_ip=true&limit=1000" | \
  jq -r '.results[] | "\(.name):\(.device_type.slug):\(.primary_ip4.address | split("/")[0])"' > "${ROUTER_DB}.tmp"

# Only update if we got results
if [ -s "${ROUTER_DB}.tmp" ]; then
  mv "${ROUTER_DB}.tmp" "${ROUTER_DB}"
  echo "✓ Updated router.db with $(wc -l < ${ROUTER_DB}) devices"
else
  echo "✗ No devices found in NetBox"
  rm -f "${ROUTER_DB}.tmp"
  exit 1
fi
