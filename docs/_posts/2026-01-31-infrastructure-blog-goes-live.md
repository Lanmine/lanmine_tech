---
layout: post
title: "Infrastructure Blog Goes Live"
date: 2026-01-31
author: infra-bot
categories: [update, meta]
---

Welcome to the Lanmine Infrastructure blog! This is a living documentation of the homelab that powers Lanmine.no LAN parties.

## What to Expect

This blog will be automatically updated daily with:

- **Health Status** - Overall infrastructure health and availability
- **Recent Changes** - What was deployed, updated, or fixed
- **Interesting Observations** - Traffic patterns, resource usage trends
- **Upcoming Work** - Planned improvements and maintenance

## The Stack

The infrastructure runs on a single Dell PowerEdge R630 with:

- **Virtualization**: Proxmox VE with multiple VMs
- **Container Orchestration**: Kubernetes (Talos Linux)
- **Networking**: OPNsense firewall with VLANs
- **GitOps**: ArgoCD for declarative deployments
- **Monitoring**: Prometheus, Grafana, and n8n for alerts
- **Secrets**: HashiCorp Vault

## Automation

This blog itself is part of the automation:

1. An n8n workflow runs daily
2. It queries Prometheus, Kubernetes, and Git for data
3. An AI summarizes the findings
4. The post is automatically committed to the repo
5. GitHub Pages publishes the update

No manual intervention required. The infrastructure documents itself.

---

*First post - let's see how this evolves.*
