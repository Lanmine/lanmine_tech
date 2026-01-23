# SNMP Exporter - NetBox Integration

## Overview

Configure SNMP exporter to dynamically discover switch targets from NetBox instead of static ServiceMonitor configuration.

## Approach

Use Prometheus `file_sd_configs` (file service discovery) with a sidecar container that periodically queries NetBox API and generates target files.

## Architecture

```
┌─────────┐     API      ┌────────────────┐
│ NetBox  │ ────────────> │ NetBox Sync    │
│   API   │              │   Sidecar      │
└─────────┘              └────────────────┘
                                 │
                                 v writes
                         ┌────────────────┐
                         │  targets.json  │ (shared emptyDir volume)
                         └────────────────┘
                                 │
                                 v reads
                         ┌────────────────┐
                         │ SNMP Exporter  │
                         │ (Prometheus)   │
                         └────────────────┘
```

## Implementation

### 1. NetBox Sync Sidecar

Create sidecar container that runs periodically:

```yaml
- name: netbox-sync
  image: python:3.11-alpine
  command:
    - sh
    - -c
    - |
      pip install requests
      while true; do
        python3 /scripts/sync-targets.py
        sleep 300  # 5 minutes
      done
  env:
    - name: NETBOX_URL
      value: "http://netbox.netbox.svc.cluster.local:8080"
    - name: NETBOX_TOKEN
      valueFrom:
        secretKeyRef:
          name: snmp-exporter-secrets
          key: netbox_token
  volumeMounts:
    - name: targets
      mountPath: /targets
    - name: scripts
      mountPath: /scripts
```

### 2. Sync Script (sync-targets.py)

```python
#!/usr/bin/env python3
import os
import json
import requests

NETBOX_URL = os.environ.get('NETBOX_URL')
NETBOX_TOKEN = os.environ.get('NETBOX_TOKEN')

headers = {'Authorization': f'Token {NETBOX_TOKEN}'}

# Query active switches from NetBox
response = requests.get(
    f'{NETBOX_URL}/api/dcim/devices/',
    headers=headers,
    params={'role': 'switch', 'status': 'active'}
)

devices = response.json()['results']

# Generate Prometheus file_sd targets
targets = []
for device in devices:
    if device.get('primary_ip4'):
        ip = device['primary_ip4']['address'].split('/')[0]
        targets.append({
            'targets': [f'{ip}:161'],
            'labels': {
                'device': device['name'],
                'site': device['site']['name'],
                'role': device['role']['name'],
                'model': device['device_type']['model']
            }
        })

# Write to file
with open('/targets/snmp-targets.json', 'w') as f:
    json.dump(targets, f, indent=2)

print(f'Synced {len(targets)} devices from NetBox')
```

### 3. SNMP Exporter Configuration

Update snmp-exporter deployment to use file_sd:

```yaml
# Add volume for target files
volumes:
  - name: targets
    emptyDir: {}
  - name: scripts
    configMap:
      name: netbox-sync-script

# Mount in snmp-exporter container
volumeMounts:
  - name: targets
    mountPath: /targets
```

### 4. ServiceMonitor Update

Update ServiceMonitor to use file-based discovery:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: snmp-exporter
  namespace: monitoring
spec:
  endpoints:
    - port: http
      interval: 60s
      scrapeTimeout: 30s
      path: /snmp
      params:
        module: [if_mib]
        auth: [lanmine]
      relabelings:
        # Use file_sd_configs targets
        - sourceLabels: [__address__]
          targetLabel: __param_target
        - sourceLabels: [__param_target]
          targetLabel: instance
        - targetLabel: __address__
          replacement: snmp-exporter.snmp-exporter.svc.cluster.local:9116
        # Preserve labels from file_sd
        - action: labelmap
          regex: __meta_(.+)
```

### 5. Prometheus Configuration

Add file_sd_configs to Prometheus scrape config:

```yaml
scrape_configs:
  - job_name: 'snmp'
    file_sd_configs:
      - files:
          - '/targets/snmp-targets.json'
        refresh_interval: 5m
```

## Benefits

- **Dynamic Discovery**: Add switch to NetBox, automatic monitoring starts
- **Centralized Management**: Single source of truth for all tools
- **Reduced Duplication**: No need to update multiple configs
- **Metadata Enrichment**: Prometheus labels inherit from NetBox (site, role, model)
- **Scale**: Hundreds of devices without ServiceMonitor bloat

## Alternative: Prometheus Operator

Could also use Prometheus Operator's `ScrapeConfig` CRD with HTTP service discovery pointing directly at NetBox API.

## Current Status

- SNMP exporter: Static targets in ServiceMonitor
- NetBox: Deployed but no integrations yet
- Next step: Implement sidecar pattern
