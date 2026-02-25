# OPNsense Monitoring with Prometheus & Grafana

**Date:** 2026-01-22
**Status:** Approved
**Owner:** Infrastructure Team

## Overview

Add comprehensive monitoring for the OPNsense firewall (10.0.10.1) using the existing Kubernetes monitoring stack (Prometheus, Grafana). This enables advanced metric correlation, troubleshooting, and customizable dashboards for firewall performance and health.

## Architecture

### Data Flow

```
OPNsense (10.0.10.1)
├── OS Node Exporter (port 9100)
│   └── System metrics (CPU, RAM, disk, network)
│
└── OPNsense API (HTTPS)
    └── Gateway events, services, Unbound DNS stats
                    ↓
        OPNsense API Exporter
        (Kubernetes deployment)
        └── Scrapes API every 15s
        └── Exposes on port 9090
                    ↓
        ServiceMonitors (2 targets)
        ├── opnsense-system (9100)
        └── opnsense-api (9090)
                    ↓
        Prometheus Operator
                    ↓
        Prometheus Database
                    ↓
        Grafana Dashboards
```

### Components

1. **OS Node Exporter** (OPNsense plugin): Exposes system metrics on port 9100
2. **OPNsense API Exporter** (Kubernetes): Queries OPNsense API, exposes metrics on port 9090
3. **ExternalSecret**: Syncs API credentials from Vault
4. **ServiceMonitors**: Configure Prometheus scraping for both exporters
5. **ArgoCD Application**: Manages deployment declaratively from git
6. **Grafana Dashboards**: Pre-built dashboards for visualization

## Kubernetes Deployment

### Directory Structure

```
kubernetes/apps/opnsense-exporter/
├── kustomization.yaml
├── namespace.yaml
├── deployment.yaml              # API Exporter deployment
├── service.yaml                # ClusterIP service
├── externalsecret.yaml         # Vault integration
├── servicemonitor-api.yaml     # Scrapes API exporter
├── servicemonitor-node.yaml    # Scrapes OPNsense directly
└── dashboards/
    ├── opnsense-overview.json
    └── opnsense-system.json
```

### OPNsense API Exporter Deployment

**Container Image:** `ghcr.io/AthennaMind/opnsense-exporter:latest`

**Environment Variables:**
- `OPNSENSE_API_URL`: https://10.0.10.1
- `OPNSENSE_API_KEY`: From ExternalSecret
- `OPNSENSE_API_SECRET`: From ExternalSecret

**Resources:**
- CPU: 100m request, 200m limit
- Memory: 128Mi request, 256Mi limit

**Replicas:** 1 (no HA needed)

**Port:** 9090 (metrics endpoint)

### ExternalSecret Configuration

**Vault Path:** `secret/infrastructure/opnsense`

**Expected Keys:**
- `api_key`: OPNsense API key
- `api_secret`: OPNsense API secret
- `api_url`: https://10.0.10.1

**Target Secret:** `opnsense-exporter-credentials` in `opnsense-exporter` namespace

**Refresh Interval:** 1h (default)

### ServiceMonitor Configuration

**servicemonitor-api.yaml:**
- Target: `opnsense-exporter:9090` (Kubernetes service)
- Scrape interval: 30s
- Path: `/metrics`
- Labels for service discovery

**servicemonitor-node.yaml:**
- Target: `10.0.10.1:9100` (direct to OPNsense)
- Scrape interval: 30s
- Path: `/metrics`
- Static endpoint configuration

### Grafana Dashboards

**Deployment Method:** ConfigMap with `grafana_dashboard: "1"` label for auto-discovery

**Dashboards:**
1. **opnsense-overview.json**: Gateway status, services, CARP
2. **opnsense-system.json**: CPU, memory, disk, network (Node Exporter metrics)

**Source:** antenna mind GitHub repository (pre-built dashboards)

## OPNsense Configuration

### 1. Install OS Node Exporter Plugin

**Steps:**
1. System → Firmware → Plugins
2. Search and install: `os-node-exporter`
3. Services → Node Exporter

**Configuration:**
- Listen Address: `10.0.10.1:9100`
- Enabled Collectors: CPU, memory, filesystem, network, loadavg
- **Security**: Do NOT expose on WAN interface

**Verification:**
```bash
curl http://10.0.10.1:9100/metrics
```

### 2. Create API User

**User Details:**
- Username: `prometheus-exporter`
- Generate API key and secret
- Save credentials for Vault

**Required Privileges:**
- Diagnostics: Gateway
- Services: Unbound DNS
- Status: Services
- System: Firmware

### 3. Enable Extended Statistics

**Unbound DNS:**
- Services → Unbound DNS → General Settings
- Enable "Extended Statistics"

**Gateway Monitoring:**
- System → Gateways → Single → [Gateway]
- Enable "Monitor Delay" and "Monitor Loss"

### 4. Firewall Rules

**Rule:**
- Source: Kubernetes pod network (10.0.10.30-32)
- Destination: 10.0.10.1:9100
- Protocol: TCP
- Action: Allow

## Vault Configuration

### Secret Path

`secret/infrastructure/opnsense`

### Keys and Values

```json
{
  "api_key": "<generated-from-opnsense>",
  "api_secret": "<generated-from-opnsense>",
  "api_url": "https://10.0.10.1"
}
```

### Population Methods

**Option 1: Vault MCP Tool**
```bash
# Use mcp__vault__write_secret tool
```

**Option 2: Vault CLI**
```bash
vault kv put secret/infrastructure/opnsense \
  api_key="<key>" \
  api_secret="<secret>" \
  api_url="https://10.0.10.1"
```

**Option 3: Ansible Integration**
- Extend existing Ansible Vault integration
- Manage credentials lifecycle with OPNsense configuration

## ArgoCD Application

**Application Manifest:** `kubernetes/infrastructure/argocd/applications/opnsense-exporter.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: opnsense-exporter
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Lanmine/lanmine_tech
    targetRevision: main
    path: kubernetes/apps/opnsense-exporter
  destination:
    server: https://kubernetes.default.svc
    namespace: opnsense-exporter
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Ansible Automation (Future Enhancement)

### Proposed Playbook

`ansible/playbooks/configure-opnsense-monitoring.yml`

**Tasks:**
1. Verify os-node-exporter plugin installed
2. Configure node exporter via API
3. Create prometheus-exporter user
4. Generate and store API credentials in Vault
5. Enable Unbound extended statistics
6. Verify firewall rules

**Implementation Strategy:**
- Phase 1: Manual configuration via web UI
- Phase 2: Create Ansible playbook for reproducibility

## Success Criteria

- [ ] OS Node Exporter running on OPNsense (port 9100)
- [ ] API Exporter deployed in Kubernetes
- [ ] Both ServiceMonitors created and scraping
- [ ] Prometheus receiving metrics from both exporters
- [ ] Grafana dashboards imported and displaying data
- [ ] ArgoCD Application synced and healthy
- [ ] Metrics visible for: CPU, memory, network, gateways, services, DNS

## Security Considerations

1. **Network Isolation**: Node Exporter only accessible from trusted networks
2. **API Credentials**: Stored in Vault, synced via ExternalSecret
3. **Least Privilege**: API user has minimum required permissions
4. **TLS**: OPNsense API accessed via HTTPS
5. **Firewall Rules**: Explicit allow rules for Kubernetes → OPNsense:9100

## References

- [antenna mind OPNsense Exporter](https://github.com/AthennaMind/opnsense-exporter)
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
- [OPNsense os-node-exporter Plugin](https://github.com/opnsense/plugins)
- YouTube Tutorial: OPNsense Monitoring with Prometheus & Grafana
