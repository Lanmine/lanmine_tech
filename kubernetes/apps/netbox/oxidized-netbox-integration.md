# Oxidized - NetBox Integration

## Overview

Configure Oxidized to use NetBox as the source of truth for network devices instead of static CSV file.

## NetBox Configuration

### 1. Add Device to NetBox

Devices must have:
- Name (becomes Oxidized hostname)
- Primary IP address
- Device role with slug "switch" or "router"
- Status: "active"
- Platform (optional): set to match Oxidized model

### 2. Custom Fields (Optional)

Create custom field on Device model:
- Name: `oxidized_model`
- Type: Text
- Default: `ios`

## Oxidized Configuration

Update Oxidized ConfigMap to use HTTP source pointing to NetBox API:

```yaml
source:
  default: http
  http:
    url: https://netbox.lionfish-caiman.ts.net/api/dcim/devices/
    scheme: https
    delimiter:
    map:
      name: name
      model: platform.slug
      ip: primary_ip4.address
    headers:
      Authorization: 'Token ${NETBOX_API_TOKEN}'
    query:
      status: active
      role: switch
```

## API Query Parameters

The Oxidized HTTP source will query:
```
GET /api/dcim/devices/?status=active&role=switch
```

Returns devices with:
- Active status
- Role "switch" (can add multiple roles: `role=switch&role=router`)

## NetBox API Response Format

```json
{
  "results": [
    {
      "id": 1,
      "name": "mgmt-sw-01",
      "platform": {
        "slug": "ios"
      },
      "primary_ip4": {
        "address": "10.0.99.101/24"
      },
      "role": {
        "slug": "switch"
      },
      "status": {
        "value": "active"
      }
    }
  ]
}
```

## Secrets Management

NetBox API token stored in Vault at: `secret/infrastructure/netbox`

Sync to Kubernetes:
```bash
cd kubernetes/apps/oxidized
./sync-secrets.sh
```

## Testing

1. Add switch to NetBox
2. Update Oxidized ConfigMap
3. Restart Oxidized: `kubectl rollout restart -n oxidized deployment/oxidized`
4. Check logs: `kubectl logs -n oxidized deployment/oxidized -f`
5. Verify backup: `kubectl exec -n oxidized deployment/oxidized -- ls -la /home/oxidized/.config/oxidized/configs.git/`

## Advantages

- Single source of truth for network inventory
- Automatic device discovery (add to NetBox = auto-backup)
- Centralized IP and device management
- Integration with other tools (SNMP exporter, Ansible)
- API-driven workflows
