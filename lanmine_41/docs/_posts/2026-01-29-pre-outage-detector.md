---
layout: post
title: "Pre-Outage Detector Workflow"
date: 2026-01-29
author: infra-bot
categories: [monitoring, n8n, automation]
---

Designing an n8n workflow that detects infrastructure issues before they cascade into outages.

## Overview

Runs every 5 minutes, checks 7 key health indicators, uses local LLM for plain-English summaries, and alerts via Discord (real-time) and Alertmanager (email).

## Goals

- Catch resource exhaustion, failing jobs, and unhealthy patterns before cascade
- Provide actionable, human-readable alerts
- Dual notification: Discord for real-time awareness, email for record

## Architecture

```
Schedule (5 min) → Parallel Checks (7) → Aggregate Findings
                                              ↓
                                         Issues? ─── No → Log healthy
                                              ↓ Yes
                                         LLM: Summarize
                                              ↓
                              ┌───────────────┴───────────────┐
                              ↓                               ↓
                        Alertmanager                      Discord
                        (email)                        (real-time)
```

## Health Checks

| Check | Method | Threshold | Severity |
|-------|--------|-----------|----------|
| Flux controller health | kubectl | Any not Ready | Critical |
| Pod restart velocity | Prometheus | >3 in 15min | Warning |
| PV stuck in Released | kubectl | Any >1h | Warning |
| CronJob missed windows | Prometheus | Missed >2 runs | Warning |
| Pending pods | Prometheus | Pending >5min | Warning |
| HelmRelease failures | kubectl | Not Ready >10min | Critical |
| Storage pressure | Prometheus | <15% available | Warning |

## LLM Integration

**Model**: Ollama (local, CPU-based)

**Task**: Plain English summary of findings

**Prompt** (~150 tokens):
```
You are a sysadmin assistant. Summarize these infrastructure
findings in 1-2 sentences for an alert. Be specific about
what's wrong and urgency.

Findings:
{findings_json}
```

**Timeout**: 30 seconds

**Fallback** (if LLM fails):
```
Pre-outage detected: {count} issues found. Check: {issue_list}
```

## Notification Formats

### Discord Embed
- Color: Red (critical), Yellow (warning), Green (healthy)
- Title: "Pre-Outage Alert" or "Infrastructure Healthy"
- Description: LLM-generated summary
- Fields: Individual check results

### Alertmanager
```json
{
  "labels": {
    "alertname": "PreOutageDetected",
    "severity": "warning"
  },
  "annotations": {
    "summary": "Pre-outage pattern detected",
    "description": "{llm_summary}"
  }
}
```

## Error Handling

| Failure | Handling |
|---------|----------|
| Kubernetes API unreachable | Note "k8s API down" in alert |
| Prometheus unreachable | Note "Prometheus down" in alert |
| LLM timeout | Use fallback template |
| Discord fails | Continue with Alertmanager |
| Alertmanager fails | Continue with Discord |
| Both fail | Write to execution log |

## Testing Plan

1. Deploy workflow in disabled state
2. Manually trigger via webhook
3. Inject mock "bad" data to verify detection
4. Verify both channels receive alerts
5. Enable 5-minute schedule
