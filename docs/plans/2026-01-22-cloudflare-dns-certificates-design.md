# Cloudflare DNS and Certificate Management Design

**Date:** 2026-01-22
**Domain:** hl0.dev
**Status:** Design Complete, Ready for Implementation

## Overview

Implement automated DNS record management and SSL certificate provisioning for Kubernetes services using Cloudflare DNS and Let's Encrypt, running parallel to the existing Tailscale setup.

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

**Cloudflare API**
- Domain: hl0.dev (active)
- Zone ID: 283c74f5bfbbb2a804dabdb938ccde8f
- API token stored in Vault at `secret/infrastructure/cloudflare`

### DNS Record Pattern

**Public DNS, Private IPs:**
- DNS records are publicly queryable (`dig grafana.hl0.dev`)
- Records resolve to private IPs (10.0.10.x on LAN)
- Accessible from LAN, VPN, or anywhere with route to 10.0.10.0/24
- No internet exposure required

**Example DNS records:**
```
grafana.hl0.dev     A  10.0.10.40
argocd.hl0.dev      A  10.0.10.40
*.hl0.dev           A  10.0.10.40  (wildcard option)
```

All records point to Traefik LoadBalancer IP (10.0.10.40).

### Certificate Acquisition Flow

1. User creates Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod`
2. cert-manager detects Certificate request
3. Initiates ACME DNS-01 challenge with Let's Encrypt
4. Let's Encrypt requests: "Create TXT record `_acme-challenge.grafana.hl0.dev` = random-value"
5. cert-manager creates TXT record via Cloudflare API
6. Let's Encrypt verifies TXT record exists via DNS query
7. Let's Encrypt issues certificate (valid 90 days)
8. cert-manager stores certificate in Kubernetes Secret
9. cert-manager deletes temporary TXT record
10. Ingress uses certificate from Secret

**Renewal:** Automatic at 60 days (30 days before expiry).

## Deployment Strategy

### Phase 1: Preparation
1. Create Kubernetes Secret with Cloudflare API token (from Vault)
2. Deploy external-dns in dry-run mode
3. Verify external-dns detects Ingresses correctly (logs only, no DNS changes)

### Phase 2: DNS Management
4. Enable external-dns live mode (creates DNS records)
5. Verify DNS records appear in Cloudflare
6. Test DNS resolution from LAN and external

### Phase 3: Certificate Management
7. Create Let's Encrypt ClusterIssuer (letsencrypt-prod)
8. Test with single service (Grafana)
9. Verify certificate issued successfully
10. Test HTTPS access at https://grafana.hl0.dev

### Phase 4: Rollout
11. Create Cloudflare Ingresses for other services as needed
12. Monitor certificate renewals

## Integration Patterns

### Dual-Access Pattern (Recommended)

Each service maintains both Tailscale and Cloudflare access:

```yaml
---
# Existing Tailscale Ingress (no changes)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-tailscale
  namespace: monitoring
spec:
  ingressClassName: tailscale
  rules:
  - host: grafana.lionfish-caiman.ts.net
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80

---
# NEW Cloudflare DNS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-cloudflare
  namespace: monitoring
  annotations:
    external-dns.alpha.kubernetes.io/hostname: grafana.hl0.dev
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - grafana.hl0.dev
    secretName: grafana-hl0-tls
  rules:
  - host: grafana.hl0.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
```

**Result:**
- Tailscale: https://grafana.lionfish-caiman.ts.net (unchanged)
- Cloudflare: https://grafana.hl0.dev (new)

### Component Configuration

**external-dns Configuration:**
```yaml
args:
  - --source=ingress
  - --source=service
  - --provider=cloudflare
  - --domain-filter=hl0.dev
  - --txt-owner-id=k8s-talos-cluster
  - --policy=sync
  - --registry=txt
  - --txt-prefix=_externaldns.
```

**ClusterIssuer Configuration:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@hl0.dev
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

## Namespace Structure

- `external-dns` - external-dns controller deployment
- `cert-manager` - ClusterIssuer resources (namespace already exists)
- Application namespaces - Certificate and Ingress resources

## Security

**Cloudflare API Token Permissions:**
- Zone → Zone → Read (list zones)
- Zone → DNS → Edit (create/update/delete DNS records)
- Scoped to: hl0.dev zone only

**Secret Management:**
- Token stored in Vault: `secret/infrastructure/cloudflare`
- Synced to Kubernetes via ExternalSecret (external-secrets-operator)
- Used by: external-dns, cert-manager

**Certificate Storage:**
- TLS certificates stored as Kubernetes Secrets
- One Secret per certificate
- Automatic rotation via cert-manager

## Comparison: Tailscale vs Cloudflare

| Aspect | Tailscale Ingress | Cloudflare DNS Ingress |
|--------|------------------|------------------------|
| DNS | `*.lionfish-caiman.ts.net` | `*.hl0.dev` |
| Certificate Authority | Tailscale | Let's Encrypt |
| Access | Tailscale network only | LAN, VPN, or routed networks |
| DNS Control | Tailscale-managed | User-controlled (Cloudflare) |
| Setup | Automatic via operator | Annotation per Ingress |
| Certificate Validity | Tailscale-managed | 90 days, auto-renewed at 60 |
| Public DNS | No | Yes (but private IPs) |

## Implementation Files

**New files to create:**
```
kubernetes/infrastructure/external-dns/
  ├── namespace.yaml
  ├── externalsecret.yaml
  ├── deployment.yaml
  ├── clusterrole.yaml
  ├── clusterrolebinding.yaml
  ├── serviceaccount.yaml
  └── kustomization.yaml

kubernetes/infrastructure/cert-manager/
  ├── cloudflare-secret.yaml (ExternalSecret)
  └── letsencrypt-issuer.yaml (ClusterIssuer)

kubernetes/apps/*/
  └── ingress-cloudflare.yaml (per service as needed)
```

**Updated files:**
```
kubernetes/infrastructure/argocd/applications/
  └── external-dns.yaml (new ArgoCD Application)
```

## Testing Plan

1. **DNS Creation Test**
   - Create test Ingress with external-dns annotation
   - Verify DNS record appears in Cloudflare
   - Test resolution: `dig grafana.hl0.dev`

2. **Certificate Acquisition Test**
   - Create Certificate resource
   - Monitor cert-manager logs for DNS-01 challenge
   - Verify TXT record created/deleted
   - Verify certificate Secret created
   - Check certificate validity: `openssl x509 -in cert.pem -text`

3. **End-to-End Test**
   - Access https://grafana.hl0.dev from browser
   - Verify valid Let's Encrypt certificate
   - Verify service functionality

4. **Renewal Test**
   - Fast-forward test by creating cert with short validity
   - Verify automatic renewal triggers

## Rollback Plan

If issues occur:

1. **DNS Issues**: Delete external-dns deployment, manually clean DNS records
2. **Certificate Issues**: Revert to existing self-signed CA issuer
3. **Full Rollback**: Delete all Cloudflare Ingresses, remove external-dns

Tailscale ingresses remain unaffected throughout.

## Success Criteria

- [ ] external-dns automatically creates DNS records for annotated Ingresses
- [ ] DNS records resolve to Traefik LoadBalancer IP (10.0.10.40)
- [ ] cert-manager successfully issues Let's Encrypt certificates via DNS-01
- [ ] Certificates auto-renew before expiry
- [ ] Services accessible via both Tailscale and Cloudflare DNS URLs
- [ ] No disruption to existing Tailscale ingresses

## Future Enhancements

- Wildcard certificate for `*.hl0.dev` (single cert for all services)
- External DNS records for non-Kubernetes services (OPNsense, standalone VMs)
- Cloudflare WAF rules (if needed)
- Let's Encrypt staging issuer for testing

## References

- Domain: hl0.dev
- Cloudflare Zone ID: 283c74f5bfbbb2a804dabdb938ccde8f
- Traefik LoadBalancer IP: 10.0.10.40
- Vault path: secret/infrastructure/cloudflare
- external-dns: https://github.com/kubernetes-sigs/external-dns
- cert-manager: https://cert-manager.io/
