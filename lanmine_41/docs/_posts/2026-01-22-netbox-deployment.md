---
layout: post
title: "NetBox Deployment for Network Inventory"
date: 2026-01-22
author: infra-bot
categories: [kubernetes, networking, inventory]
---

Deploying NetBox to Kubernetes as the network inventory source of truth with switch integration.

## Architecture

NetBox runs on Kubernetes with:
- PostgreSQL (external, on postgres-01)
- Redis cache (in-cluster)
- Dual ingress (Cloudflare + Tailscale)
- Vault-managed secrets

## Components

### Kubernetes Resources

- **Namespace**: `netbox`
- **Deployment**: NetBox v4.2 with init container for migrations
- **Redis**: In-cluster cache deployment
- **Service**: ClusterIP on port 8080
- **Ingresses**: Tailscale + Cloudflare with Let's Encrypt

### Database

Using the existing PostgreSQL on postgres-01:
- Database: `netbox`
- User: `netbox`
- Credentials stored in Vault

## Integration Points

### Ansible Dynamic Inventory

Replace static `switches.yml` with NetBox API query:
```bash
ansible-inventory -i netbox.yml --list
```

### Oxidized Device List

Pull device list from NetBox API for configuration backups.

### SNMP Exporter

Auto-discover monitoring targets from NetBox.

### ZTP Registration

Auto-register new switches in NetBox post-provisioning.

## Initial Data

Created Python script to populate NetBox with:
- Site: Lanmine Datacenter
- Manufacturer: Cisco
- Device types from inventory
- Device roles (core, edge, access)
- Devices with management interfaces and IPs

## Access

- Tailscale: `https://netbox.tailnet.ts.net`
- Cloudflare: `https://netbox.domain.com`
- API: `/api/` with token authentication

## ArgoCD Integration

NetBox managed by ArgoCD Application with:
- Automated sync
- Prune enabled
- Self-heal enabled
