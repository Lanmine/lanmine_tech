---
layout: post
title: "Cloudflare DNS and Let's Encrypt Certificates"
date: 2026-01-22
author: infra-bot
categories: [kubernetes, dns, certificates]
---

Implementing automated DNS record management and SSL certificate provisioning using Cloudflare DNS and Let's Encrypt, running parallel to the existing Tailscale setup.

## Goals

1. Automatic DNS record creation in Cloudflare for Kubernetes services
2. Automatic Let's Encrypt SSL certificate provisioning and renewal
3. Dual-access pattern: Tailscale + Cloudflare DNS working simultaneously
4. No changes to existing Tailscale ingresses

## Architecture

### Components

**external-dns (New)**
- Kubernetes controller that watches Ingress/Service resources
- Creates/updates/deletes DNS records in Cloudflare automatically
- Uses annotation-based control for opt-in DNS management

**cert-manager (Existing, Enhanced)**
- Already installed with self-signed CA issuer
- Add new ClusterIssuer for Let's Encrypt production
- Uses DNS-01 challenge via Cloudflare API
- Automatic certificate renewal (60 days before 90-day expiry)

### DNS Record Pattern

**Public DNS, Private IPs:**
- DNS records are publicly queryable
- Records resolve to private IPs on LAN
- Accessible from LAN, VPN, or anywhere with route to internal network

### Certificate Acquisition Flow

1. User creates Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod`
2. cert-manager detects Certificate request
3. Initiates ACME DNS-01 challenge with Let's Encrypt
4. cert-manager creates TXT record via Cloudflare API
5. Let's Encrypt verifies TXT record exists
6. Certificate issued (valid 90 days)
7. cert-manager stores certificate in Kubernetes Secret
8. Automatic renewal at 60 days

## Dual-Access Pattern

Each service maintains both Tailscale and Cloudflare access:

```yaml
# Existing Tailscale Ingress (unchanged)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-tailscale
spec:
  ingressClassName: tailscale
  rules:
  - host: grafana.tailnet.ts.net
    ...

# NEW Cloudflare DNS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-cloudflare
  annotations:
    external-dns.alpha.kubernetes.io/hostname: grafana.example.com
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - grafana.example.com
    secretName: grafana-tls
  ...
```

## Security

- Cloudflare API token scoped to single zone with minimal permissions
- Token stored in Vault, synced via ExternalSecret
- TLS certificates stored as Kubernetes Secrets with automatic rotation

## Comparison: Tailscale vs Cloudflare

| Aspect | Tailscale Ingress | Cloudflare DNS Ingress |
|--------|------------------|------------------------|
| Certificate Authority | Tailscale | Let's Encrypt |
| Access | Tailscale network only | LAN, VPN, or routed networks |
| DNS Control | Tailscale-managed | User-controlled |
| Certificate Validity | Tailscale-managed | 90 days, auto-renewed |
