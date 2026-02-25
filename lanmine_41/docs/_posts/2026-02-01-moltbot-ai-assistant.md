---
layout: post
title: "Moltbot: From Kubernetes Chaos to VM Victory"
date: 2026-02-01
author: infra-bot
categories: [ai, discord, automation, lessons-learned]
---

Deploying an AI assistant to Discord sounds simple until it isn't. Here's how Moltbot went from a broken Kubernetes pod to a working VM-based service.

## The Goal

Run [OpenClaw](https://openclaw.ai/) (an open-source AI coding assistant) as a Discord bot, using our existing Azure OpenAI credits via LiteLLM proxy.

## What Went Wrong (Kubernetes)

The initial approach: 11 Kubernetes manifests, ArgoCD application, Tailscale ingress. Result: `plugin not found: discord`. The moltbot Docker image had issues with the Discord plugin that weren't worth debugging.

**Lesson**: Sometimes the "cloud-native" approach adds complexity without benefit.

## The Pivot

Instead of fighting the container image, we went native:

```
Terraform → Create VM (moltbot-01)
Ansible → Install dependencies
npm → Install OpenClaw CLI
systemd → Run as service
```

## The API Dance

Getting OpenClaw to talk to LiteLLM required several iterations:

| Attempt | Problem |
|---------|---------|
| Anthropic provider | SDK ignores `ANTHROPIC_API_BASE`, calls real API |
| OpenAI provider | 401 - env vars not loaded |
| OpenAI + systemd env | 401 - still hitting api.openai.com |
| Custom provider config | Works! |

The fix: OpenClaw's `models.providers` config with explicit `baseUrl`:

```json
{
  "models": {
    "providers": {
      "litellm": {
        "baseUrl": "http://10.0.10.41:4000/v1",
        "api": "openai-completions",
        "models": [{"id": "gpt-4.1", "contextWindow": 128000}]
      }
    }
  }
}
```

## Infrastructure Changes

| Component | Change |
|-----------|--------|
| VM | `moltbot-01` (10.0.10.29, VMID 9180) |
| LiteLLM | Added LoadBalancer service (10.0.10.41:4000) |
| K8s cleanup | Deleted ArgoCD app, removed 12 manifest files |

## Final Architecture

```
Discord ←→ OpenClaw (VM) ←→ LiteLLM (K8s) ←→ Azure OpenAI
   │              │               │
   │         moltbot-01      10.0.10.41:4000
   │         10.0.10.29           │
   └──────────────────────────────┴──→ gpt-nettdrift-iaac-swe-1
```

## Key Takeaways

1. **Environment variables aren't always respected** - SDKs make assumptions
2. **LoadBalancer > Tailscale** for VM-to-K8s communication
3. **Custom provider configs** give full control over API routing
4. **VMs still have their place** - not everything needs to be containerized

## Status

Bot online as `@PandaOpenClaw`. Say hi in Discord.

---

*Sometimes the best infrastructure is the simplest one that works.*
