# Network Topology Documentation

**Last updated:** 2026-01-23

## Network Overview

The Lanmine infrastructure uses a segmented VLAN architecture with centralized management and monitoring.

## VLANs

| VLAN | Name | Subnet | Gateway | Purpose |
|------|------|--------|---------|---------|
| 1 | default | - | - | Unused (default VLAN) |
| 10 | Infrastructure | 10.0.10.0/24 | 10.0.10.1 | Core infrastructure services |
| 20 | Contestants | 10.0.20.0/23 | 10.0.20.1 | LAN party contestant network |
| 30 | OOB | 10.0.30.0/24 | 10.0.30.1 | Out-of-band management (iDRAC, IPMI) |
| 99 | MGMT | 10.0.99.0/24 | 10.0.99.1 | Switch management network |

## Network Devices

### Core Infrastructure

| Device | IP | Role | Location | Monitoring |
|--------|-----|------|----------|------------|
| opnsense | 10.0.10.1 | Firewall/Gateway | Proxmox VM | SNMP, Syslog, NetFlow |
| proxmox | 10.0.10.5 | Hypervisor | Physical server | SNMP, Syslog |
| mgmt-sw-01 | 10.0.99.101 | Access switch | Rack 1 | SNMP, Syslog, Oxidized |

### Infrastructure Services (VLAN 10)

| Service | IP | Purpose | VM Type |
|---------|-----|---------|---------|
| vault-01 | 10.0.10.21 | Secrets management | Ubuntu VM |
| runner-01 | 10.0.10.22 | GitHub Actions | Ubuntu VM |
| postgres-01 | 10.0.10.23 | Database (Terraform state, NetBox) | Ubuntu VM |
| authentik-01 | 10.0.10.25 | SSO/Identity provider | Ubuntu VM |
| akvorado-01 | 10.0.10.26 | NetFlow collector | Ubuntu VM |
| n8n-01 | 10.0.10.27 | Workflow automation | Ubuntu VM |
| panda9000 | 10.0.10.28 | Panda cam viewer | Ubuntu VM |
| talos-cp-01 | 10.0.10.30 | Kubernetes control plane | Talos Linux |
| talos-worker-01 | 10.0.10.31 | Kubernetes worker | Talos Linux |
| talos-worker-02 | 10.0.10.32 | Kubernetes worker | Talos Linux |
| Traefik LB | 10.0.10.40 | Kubernetes ingress | MetalLB VIP |
| Loki | 10.0.10.49 | Log aggregation | MetalLB VIP |
| Alloy-Syslog | 10.0.10.50 | Syslog receiver | MetalLB VIP |

### Contestant Network (VLAN 20)

| Service | IP | Purpose |
|---------|-----|---------|
| ubuntu-mgmt02 | 10.0.20.2 | LANcache server | Physical (Dell R630) |

## Switch Port Assignments (mgmt-sw-01)

### Gigabit Ethernet Ports

| Port | VLAN | Status | Description |
|------|------|--------|-------------|
| Gi1/0/1-4 | 20 | Up (1,10,22,24) | Contestants |
| Gi1/0/5-9 | 10 | Down | Infrastructure (reserved) |
| Gi1/0/10 | 30 | Up | OOB Management |
| Gi1/0/11-21 | 10 | Down | Infrastructure (reserved) |
| Gi1/0/22 | 20 | Up | Contestants |
| Gi1/0/23 | 10 | Down | Infrastructure (reserved) |
| Gi1/0/24 | - | Up (trunk) | - |

### 10 Gigabit Ethernet Ports

| Port | VLAN | Status | Description |
|------|------|--------|-------------|
| Te1/0/1 | - | Up (trunk) | Uplink to core |
| Te1/0/2 | 1 | Down | Unused |

### Management

| Interface | IP | Description |
|-----------|-----|------------|
| Vlan99 | 10.0.99.101 | Switch management interface |

## Network Services

### Monitoring Stack

- **SNMP Exporter**: Collects metrics from all infrastructure devices
- **Prometheus**: Metrics storage and alerting
- **Grafana**: Visualization dashboards
- **Loki**: Centralized syslog aggregation
- **Alloy**: Syslog receiver and processor

### Configuration Management

- **Oxidized**: Automated switch config backups (Git storage)
- **NetBox**: Source of truth for network inventory
- **Ansible**: Configuration automation with dynamic inventory

### Flow Analysis

- **Akvorado**: NetFlow/IPFIX collector and analyzer
  - Sources: OPNsense firewall (NetFlow v9)
  - Note: Catalyst 2960-X does not support NetFlow export

## Network Topology Diagram

```
Internet
    |
[OPNsense Firewall] 10.0.10.1
    |
    +--- VLAN 10 (Infrastructure) --- [Proxmox] 10.0.10.5
    |         |
    |         +--- VMs: vault, runner, postgres, authentik, akvorado, n8n, panda
    |         +--- Kubernetes Cluster (Talos)
    |                 |
    |                 +--- Control Plane: 10.0.10.30
    |                 +--- Workers: 10.0.10.31, 10.0.10.32
    |                 +--- MetalLB VIPs: 10.0.10.40-49
    |
    +--- VLAN 20 (Contestants) --- [LANcache] 10.0.20.2 (ubuntu-mgmt02)
    |
    +--- VLAN 30 (OOB Management)
    |
    +--- VLAN 99 (Switch Management) --- [mgmt-sw-01] 10.0.99.101
```

## Connectivity

### Uplinks

- **mgmt-sw-01 Te1/0/1**: 10G trunk uplink to core network
- **OPNsense**: WAN interface to ISP

### Inter-VLAN Routing

All inter-VLAN routing handled by OPNsense firewall (10.0.10.1).

## Security

- **Firewall**: OPNsense with zone-based policies
- **Authentication**: Centralized via Authentik (LDAP/OAuth)
- **Secrets**: HashiCorp Vault (file storage backend)
- **Switch passwords**: Rotated, stored in Vault
- **SNMP**: SNMPv3 with SHA auth + AES encryption

## Monitoring Endpoints

- Grafana: https://grafana.lionfish-caiman.ts.net
- Prometheus: Internal cluster service
- NetBox: https://netbox.lionfish-caiman.ts.net
- Akvorado: https://akvorado.lionfish-caiman.ts.net
- Uptime Kuma: https://uptime.lionfish-caiman.ts.net

## Notes

- All Tailscale URLs use the `lionfish-caiman.ts.net` tailnet
- Public access via Cloudflare on `hl0.dev` domain
- NetBox serves as source of truth for all network inventory
- Ansible dynamic inventory pulls from NetBox automatically
