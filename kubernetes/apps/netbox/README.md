# NetBox - Network Source of Truth

## Overview

NetBox serves as the centralized inventory and IPAM system for network infrastructure at Lanmine.

**Access:**
- Tailscale: https://netbox.lionfish-caiman.ts.net
- Cloudflare: https://netbox.hl0.dev

## Current Status

- **Deployed**: ✅ Running in netbox namespace
- **Version**: v4.2 (netboxcommunity/netbox)
- **Database**: PostgreSQL
- **Cache**: Redis
- **Ingress**: Tailscale + Cloudflare

## Integrations

### Planned Integrations

| Tool | Status | Purpose | Documentation |
|------|--------|---------|---------------|
| Oxidized | Planned | Device list for config backup | [oxidized-netbox-integration.md](oxidized-netbox-integration.md) |
| SNMP Exporter | Planned | Dynamic target discovery | [snmp-exporter-netbox-integration.md](snmp-exporter-netbox-integration.md) |
| Ansible | Planned | Dynamic inventory | TBD |

### Integration Benefits

- **Single Source of Truth**: Manage devices in one place
- **Automatic Discovery**: Add device to NetBox → tools auto-configure
- **Metadata Enrichment**: Site, role, model propagate to monitoring
- **API-Driven**: All integrations use NetBox REST API

## Adding Devices

### Quick Add: mgmt-sw-01

```bash
export NETBOX_URL="https://netbox.lionfish-caiman.ts.net"
export NETBOX_TOKEN="$(kubectl get secret -n netbox netbox-superuser -o jsonpath='{.data.api-token}' | base64 -d)"
./add-switch-to-netbox.sh
```

### Manual Add via Web UI

1. Navigate to https://netbox.lionfish-caiman.ts.net
2. Login (admin credentials in Vault: `secret/infrastructure/netbox`)
3. Devices → Add Device
4. Fill in:
   - Name: `mgmt-sw-01`
   - Site: `Lanmine`
   - Device Type: `Catalyst 3560CX-12PC-S`
   - Role: `Switch`
   - Status: `Active`
5. IPAM → IP Addresses → Add
   - Address: `10.0.99.101/24`
   - Assign to: `mgmt-sw-01`
6. Set as Primary IP

## API Usage

### Authentication

API token stored in Vault: `secret/infrastructure/netbox`

```bash
export NETBOX_TOKEN="$(kubectl get secret -n netbox netbox-superuser -o jsonpath='{.data.api-token}' | base64 -d)"
```

### Common Queries

**List all devices:**
```bash
curl -H "Authorization: Token $NETBOX_TOKEN" \
  https://netbox.lionfish-caiman.ts.net/api/dcim/devices/
```

**Get active switches:**
```bash
curl -H "Authorization: Token $NETBOX_TOKEN" \
  "https://netbox.lionfish-caiman.ts.net/api/dcim/devices/?role=switch&status=active"
```

**Get device by name:**
```bash
curl -H "Authorization: Token $NETBOX_TOKEN" \
  "https://netbox.lionfish-caiman.ts.net/api/dcim/devices/?name=mgmt-sw-01"
```

## Data Model

### Required for Switch Monitoring

- **Device**
  - Name (unique identifier)
  - Site (location)
  - Device Type (model)
  - Role (switch, router, firewall)
  - Status (active, planned, offline)
  - Primary IP (management IP)

- **IP Address**
  - Address (10.0.99.101/24)
  - Status (active)
  - Assigned to device

### Optional Enrichment

- **Platform**: OS/vendor (ios, nxos)
- **Serial Number**: Asset tracking
- **Rack Position**: Physical location
- **Interfaces**: Port inventory
- **Cables**: Physical connections

## Secrets Management

NetBox secrets stored in Vault:

```
secret/infrastructure/netbox
├── api_token      # API authentication
└── url            # Internal cluster URL
```

Kubernetes secret sync:
```bash
cd kubernetes/apps/netbox
# (Create sync-secrets.sh when needed)
```

## Deployment

NetBox is deployed via manual manifests (not yet in git):

- Namespace: `netbox`
- Deployment: `netbox`
- Image: `netboxcommunity/netbox:v4.2`
- Database: PostgreSQL (via secrets)
- Cache: Redis deployment
- Storage: emptyDir (media/static)

**Note**: Manifests need to be added to git for GitOps management.

## Future Enhancements

### Phase 1: Basic Integrations
- [ ] Add mgmt-sw-01 to NetBox
- [ ] Configure Oxidized to use NetBox API
- [ ] Update SNMP exporter ServiceMonitor with NetBox devices

### Phase 2: Dynamic Discovery
- [ ] Implement NetBox sync sidecar for SNMP exporter
- [ ] File-based service discovery in Prometheus
- [ ] Ansible dynamic inventory from NetBox

### Phase 3: Advanced Features
- [ ] Ansible playbook to sync switch configs to NetBox
- [ ] Custom fields for Oxidized model mapping
- [ ] Integration with ZTP workflow
- [ ] NetBox as DHCP reservation source

## Resources

- [NetBox Documentation](https://docs.netbox.dev/)
- [NetBox API Guide](https://docs.netbox.dev/en/stable/integrations/rest-api/)
- [NetBox Docker](https://github.com/netbox-community/netbox-docker)
