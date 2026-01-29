# Pre-Outage Detector Workflow Design

## Overview

n8n workflow that detects infrastructure issues before they cascade into outages. Runs every 5 minutes, checks 7 key health indicators, uses local LLM for plain-English summaries, and alerts via both Discord (real-time) and Alertmanager (email).

## Goals

- Catch resource exhaustion, failing jobs, and unhealthy patterns before cascade
- Provide actionable, human-readable alerts
- Dual notification: Discord for real-time awareness, email for record

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Schedule   │────▶│  Parallel Checks │────▶│  Aggregate  │
│  (5 min)    │     │  (7 checks)      │     │  Findings   │
└─────────────┘     └──────────────────┘     └──────┬──────┘
                                                    │
                         ┌──────────────────────────┴───────┐
                         ▼                                  ▼
                   ┌───────────┐                     ┌─────────────┐
                   │ Issues?   │─── No ─────────────▶│ Log healthy │
                   └─────┬─────┘                     └─────────────┘
                         │ Yes
                         ▼
                   ┌─────────────────┐
                   │ LLM: Summarize  │
                   │ (Ollama, ~150t) │
                   └────────┬────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
        ┌──────────────┐           ┌──────────────┐
        │ Alertmanager │           │   Discord    │
        │ (email)      │           │  (real-time) │
        └──────────────┘           └──────────────┘
```

## Health Checks

| # | Check | Method | Query/Command | Threshold | Severity |
|---|-------|--------|---------------|-----------|----------|
| 1 | Flux controller health | kubectl (SSH) | `kubectl get pods -n flux-system -o json` | Any not Ready | Critical |
| 2 | Pod restart velocity | Prometheus | `increase(kube_pod_container_status_restarts_total[15m]) > 3` | >3 in 15min | Warning |
| 3 | PV stuck in Released | kubectl (SSH) | `kubectl get pv -o json \| jq '[.items[] \| select(.status.phase == "Released")]'` | Any Released >1h | Warning |
| 4 | CronJob missed windows | Prometheus | `time() - kube_cronjob_status_last_schedule_time` | Missed >2 runs | Warning |
| 5 | Pending pods | Prometheus | `kube_pod_status_phase{phase="Pending"} == 1` | Pending >5min | Warning |
| 6 | HelmRelease failures | kubectl (SSH) | `kubectl get helmreleases -A -o json` | Not Ready >10min | Critical |
| 7 | Storage pressure | Prometheus | `kubelet_volume_stats_available_bytes / capacity < 0.15` | <15% available | Warning |

## Check Implementations

### 1. Flux Controller Health (kubectl via SSH)
```bash
kubectl get pods -n flux-system -o json | jq '[.items[] | select(.status.phase != "Running" or (.status.containerStatuses[]?.ready == false))] | length'
```

### 2. Pod Restart Velocity (Prometheus)
```promql
sum by (namespace, pod) (
  increase(kube_pod_container_status_restarts_total[15m])
) > 3
```

### 3. Released PVs (kubectl via SSH)
```bash
kubectl get pv -o json | jq '[.items[] | select(.status.phase == "Released")] | length'
```

### 4. CronJob Missed Windows (Prometheus)
```promql
(time() - kube_cronjob_status_last_schedule_time) > 7200
```

### 5. Pending Pods (Prometheus)
```promql
kube_pod_status_phase{phase="Pending"} == 1
```

### 6. HelmRelease Failures (kubectl via SSH)
```bash
kubectl get helmreleases -A -o json | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True"))] | length'
```

### 7. Storage Pressure (Prometheus)
```promql
(kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) < 0.15
```

## LLM Integration

**Model**: Ollama at `10.0.20.2:11434` (CPU-based, small tasks only)

**Task**: Plain English summary of findings

**Prompt template** (~150 input tokens):
```
You are a sysadmin assistant. Summarize these infrastructure findings in 1-2 sentences for an alert. Be specific about what's wrong and urgency.

Findings:
{findings_json}
```

**Timeout**: 30 seconds

**Fallback** (if LLM fails):
```
Pre-outage detected: {count} issues found. Check: {issue_list}
```

## Notification Formats

### Alertmanager Payload
```json
[{
  "labels": {
    "alertname": "PreOutageDetected",
    "severity": "warning",
    "source": "n8n-preoutage"
  },
  "annotations": {
    "summary": "Pre-outage pattern detected",
    "description": "{llm_summary}"
  }
}]
```

### Discord Embed
- Color: Red (critical), Yellow (warning), Green (healthy)
- Title: "Pre-Outage Alert" or "Infrastructure Healthy"
- Description: LLM-generated summary
- Fields: Individual check results
- Timestamp: ISO 8601

## Error Handling

| Failure | Handling |
|---------|----------|
| Kubernetes API unreachable | Skip kubectl checks, note "k8s API down" in alert |
| Prometheus unreachable | Skip metric checks, note "Prometheus down" in alert |
| LLM timeout (>30s) | Use fallback template summary |
| Discord webhook fails | Log error, continue with Alertmanager |
| Alertmanager fails | Log error, continue with Discord |
| Both channels fail | Write to n8n execution log |

## Secrets Required

| Path | Key | Purpose |
|------|-----|---------|
| `secret/infrastructure/discord` | `webhook_url` | Discord webhook for alerts |
| `secret/infrastructure/ssh` | existing | SSH access to talos-cp-01 |
| existing | - | Prometheus URL (10.0.10.40/prometheus) |
| existing | - | Alertmanager URL (10.0.10.40/alertmanager) |

## Testing Plan

1. Deploy workflow in disabled state
2. Manually trigger via webhook endpoint
3. Inject mock "bad" data to verify detection
4. Verify Discord + Alertmanager both receive alerts
5. Enable 5-minute schedule after validation

## Files

- Workflow: `ansible/files/n8n-workflows/pre-outage-detector.json`
- Deployment: `ansible-playbook playbooks/deploy-n8n-workflows.yml`
