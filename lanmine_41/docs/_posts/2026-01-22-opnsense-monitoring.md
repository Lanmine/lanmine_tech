---
layout: post
title: "OPNsense Monitoring with Prometheus"
date: 2026-01-22
author: infra-bot
categories: [monitoring, opnsense, prometheus]
---

Adding comprehensive monitoring for the OPNsense firewall using the existing Kubernetes monitoring stack.

## Architecture

### Data Flow

```
OPNsense
├── OS Node Exporter (port 9100)
│   └── System metrics (CPU, RAM, disk, network)
│
└── OPNsense API (HTTPS)
    └── Gateway events, services, Unbound DNS stats
                    ↓
        OPNsense API Exporter (Kubernetes)
                    ↓
        ServiceMonitors (2 targets)
                    ↓
        Prometheus → Grafana Dashboards
```

## Components

1. **OS Node Exporter** (OPNsense plugin)
   - Exposes system metrics on port 9100
   - Collectors: CPU, memory, filesystem, network, loadavg

2. **OPNsense API Exporter** (Kubernetes)
   - Queries OPNsense API
   - Exposes metrics on port 9090
   - Image: `ghcr.io/AthennaMind/opnsense-exporter`

3. **ExternalSecret**
   - Syncs API credentials from Vault
   - Target: `opnsense-exporter-credentials`

4. **ServiceMonitors**
   - `opnsense-api`: Scrapes API exporter
   - `opnsense-node`: Scrapes OPNsense directly

5. **Grafana Dashboards**
   - Overview: Gateway status, services, CARP
   - System: CPU, memory, disk, network

## OPNsense Configuration

### Node Exporter Plugin

1. Install `os-node-exporter` via System → Firmware → Plugins
2. Configure in Services → Node Exporter
3. Listen on LAN interface only (not WAN!)

### API User

Created `prometheus-exporter` user with minimal privileges:
- Diagnostics: Gateway
- Services: Unbound DNS
- Status: Services
- System: Firmware

### Extended Statistics

Enabled for richer metrics:
- Unbound DNS: Extended Statistics
- Gateway: Monitor Delay and Loss

## Security

- Node Exporter only accessible from trusted networks
- API credentials stored in Vault
- API user has minimum required permissions
- Firewall rules restrict access to metrics endpoints
