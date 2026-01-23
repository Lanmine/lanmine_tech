#!/bin/bash
set -euo pipefail

# Add mgmt-sw-01 switch to NetBox inventory
# Requires: NETBOX_URL and NETBOX_TOKEN environment variables

NETBOX_URL="${NETBOX_URL:-https://netbox.lionfish-caiman.ts.net}"
NETBOX_TOKEN="${NETBOX_TOKEN:-}"

if [ -z "$NETBOX_TOKEN" ]; then
  echo "Error: NETBOX_TOKEN environment variable not set"
  echo "Get token from: kubectl get secret -n netbox netbox-superuser -o jsonpath='{.data.api-token}' | base64 -d"
  exit 1
fi

echo "Adding mgmt-sw-01 to NetBox..."

# Create site if not exists
echo "Creating site: Lanmine"
curl -s -X POST "${NETBOX_URL}/api/dcim/sites/" \
  -H "Authorization: Token ${NETBOX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Lanmine",
    "slug": "lanmine",
    "status": "active"
  }' || echo "Site may already exist"

# Create manufacturer if not exists
echo "Creating manufacturer: Cisco"
curl -s -X POST "${NETBOX_URL}/api/dcim/manufacturers/" \
  -H "Authorization: Token ${NETBOX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Cisco",
    "slug": "cisco"
  }' || echo "Manufacturer may already exist"

# Create device type if not exists
echo "Creating device type: Catalyst 3560CX"
curl -s -X POST "${NETBOX_URL}/api/dcim/device-types/" \
  -H "Authorization: Token ${NETBOX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "manufacturer": {"name": "Cisco"},
    "model": "Catalyst 3560CX-12PC-S",
    "slug": "catalyst-3560cx-12pc-s"
  }' || echo "Device type may already exist"

# Create device role if not exists
echo "Creating device role: Switch"
curl -s -X POST "${NETBOX_URL}/api/dcim/device-roles/" \
  -H "Authorization: Token ${NETBOX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Switch",
    "slug": "switch",
    "color": "2196f3"
  }' || echo "Device role may already exist"

# Create the device
echo "Creating device: mgmt-sw-01"
curl -s -X POST "${NETBOX_URL}/api/dcim/devices/" \
  -H "Authorization: Token ${NETBOX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mgmt-sw-01",
    "device_type": {"slug": "catalyst-3560cx-12pc-s"},
    "role": {"slug": "switch"},
    "site": {"slug": "lanmine"},
    "status": "active",
    "comments": "Management switch in rack - VLAN 99 (10.0.99.101)"
  }'

# Add primary IP
echo "Creating IP address: 10.0.99.101"
IP_RESPONSE=$(curl -s -X POST "${NETBOX_URL}/api/ipam/ip-addresses/" \
  -H "Authorization: Token ${NETBOX_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "address": "10.0.99.101/24",
    "status": "active",
    "assigned_object_type": "dcim.device",
    "assigned_object_id": null,
    "description": "Management IP on VLAN 99"
  }')

IP_ID=$(echo "$IP_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")

if [ -n "$IP_ID" ]; then
  echo "Setting primary IP for mgmt-sw-01"
  DEVICE_ID=$(curl -s "${NETBOX_URL}/api/dcim/devices/?name=mgmt-sw-01" \
    -H "Authorization: Token ${NETBOX_TOKEN}" | \
    python3 -c "import sys, json; print(json.load(sys.stdin)['results'][0]['id'])")

  curl -s -X PATCH "${NETBOX_URL}/api/dcim/devices/${DEVICE_ID}/" \
    -H "Authorization: Token ${NETBOX_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"primary_ip4\": ${IP_ID}}"
fi

echo ""
echo "✓ mgmt-sw-01 added to NetBox"
echo "View at: ${NETBOX_URL}/dcim/devices/mgmt-sw-01/"
