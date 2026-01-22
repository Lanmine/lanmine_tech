# OPNsense Node Exporter Setup

This document describes how to install and configure node_exporter on OPNsense for system metrics collection.

## Installation

SSH into OPNsense and run:

```bash
# Install node_exporter
pkg install -y node_exporter

# Enable at boot
sysrc node_exporter_enable="YES"

# Configure listen address (default :9100)
sysrc node_exporter_listen_address=":9100"

# Create textfile directory
mkdir -p /var/tmp/node_exporter
chown nobody:nobody /var/tmp/node_exporter

# Start the service
service node_exporter start

# Verify it's running
service node_exporter status
```

## Verification

```bash
# Check it's listening
sockstat -4 -l | grep 9100

# Test metrics endpoint
fetch -qo - http://localhost:9100/metrics | head -20
```

## Configuration

The rc.d script at `/usr/local/etc/rc.d/node_exporter` handles service management.

**Important:** Do NOT set `node_exporter_args="--web.listen-address=:9100"` in rc.conf as the script already sets this via `node_exporter_listen_address`. Setting both causes conflicts.

**Correct configuration:**
```bash
node_exporter_enable="YES"
node_exporter_listen_address=":9100"
```

**Incorrect configuration (causes startup failure):**
```bash
node_exporter_enable="YES"
node_exporter_args="--web.listen-address=:9100"  # Duplicate flag - will fail
```

## Firewall Rules

If Prometheus can't scrape, add a firewall rule:

- **Interface**: LAN or VLAN 10
- **Protocol**: TCP
- **Source**: 10.0.10.0/24
- **Destination**: This Firewall
- **Destination Port**: 9100
- **Action**: Pass

## Metrics Collected

Node exporter provides ~330+ metrics including:

- **CPU**: `node_cpu_seconds_total`, frequency, scaling governor
- **Memory**: `node_memory_*`
- **Disk**: `node_disk_*` (I/O, reads, writes)
- **Network**: `node_network_*` (rx/tx bytes, errors, drops)
- **Filesystem**: `node_filesystem_*` (size, free, usage)
- **Load**: `node_load1`, `node_load5`, `node_load15`
- **Boot time**: `node_boot_time_seconds`
- **Context switches**: `node_context_switches_total`
- **ZFS**: `node_zfs_*` (if ZFS is in use)

## Monitoring Stack

OPNsense monitoring consists of two exporters:

1. **Node Exporter** (on OPNsense): System metrics via port 9100
2. **API Exporter** (in Kubernetes): Firewall-specific metrics via OPNsense API

Both are scraped by Prometheus and visualized in Grafana dashboards at https://grafana.lionfish-caiman.ts.net.

## Troubleshooting

If the service won't start:

```bash
# Check for duplicate args
grep node_exporter /etc/rc.conf

# Remove conflicting args
sysrc -x node_exporter_args

# Set proper listen address
sysrc node_exporter_listen_address=":9100"

# Restart
service node_exporter restart
```

If metrics aren't being scraped, verify ServiceMonitor:

```bash
kubectl get servicemonitor -n monitoring opnsense-node-exporter -o yaml
```
