# WAN Resilience Implementation Plan

## Overview

Prepare infrastructure to remain fully operational during WAN outages, eliminating dependencies on:
- Tailscale coordination servers (*.ts.net DNS)
- Cloudflare DNS resolution
- External certificate authorities

## Architecture

**Three-tier DNS strategy:**
1. **Primary:** `lanmine.local` - Internal authoritative domain (always works)
2. **Fallback:** `hl0.dev` - Domain override in OPNsense (WAN-independent)
3. **External:** `*.ts.net` - Tailscale MagicDNS (WAN-dependent)

**Dual certificate strategy:**
1. **Internal CA:** Vault-based PKI for `.lanmine.local` (WAN-independent)
2. **Let's Encrypt:** Public CA for `.hl0.dev` (requires WAN)

## Phase 1: OPNsense DNS Configuration

### 1.1 Configure Local Domain Authority

**OPNsense → Services → Unbound DNS → Advanced**

Add custom configuration:
```
server:
  local-zone: "lanmine.local." static

  # Infrastructure VMs
  local-data: "vault.lanmine.local. IN A 10.0.10.21"
  local-data: "postgres.lanmine.local. IN A 10.0.10.23"
  local-data: "authentik.lanmine.local. IN A 10.0.10.25"
  local-data: "akvorado.lanmine.local. IN A 10.0.10.26"
  local-data: "n8n.lanmine.local. IN A 10.0.10.27"
  local-data: "proxmox.lanmine.local. IN A 10.0.10.5"
  local-data: "opnsense.lanmine.local. IN A 10.0.10.1"

  # Kubernetes services (via Traefik LoadBalancer)
  local-data: "grafana.lanmine.local. IN A 10.0.10.40"
  local-data: "netbox.lanmine.local. IN A 10.0.10.40"
  local-data: "argocd.lanmine.local. IN A 10.0.10.40"
  local-data: "prometheus.lanmine.local. IN A 10.0.10.40"
  local-data: "alertmanager.lanmine.local. IN A 10.0.10.40"
  local-data: "hubble.lanmine.local. IN A 10.0.10.40"
  local-data: "uptime.lanmine.local. IN A 10.0.10.40"
  local-data: "panda.lanmine.local. IN A 10.0.10.40"
  local-data: "glance.lanmine.local. IN A 10.0.10.40"
  local-data: "traefik.lanmine.local. IN A 10.0.10.40"
```

### 1.2 Add hl0.dev Domain Override

**OPNsense → Services → Unbound DNS → Overrides → Domain Override**

```
Domain: hl0.dev
IP: 10.0.10.40
Description: Internal Cloudflare domain override (WAN-resilient)
```

This makes ALL `*.hl0.dev` queries resolve to Traefik LoadBalancer without WAN.

## Phase 2: Internal Certificate Authority

### 2.1 Create Internal CA in Vault

```bash
# Connect to Vault
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
vault login

# Enable PKI secrets engine
vault secrets enable -path=pki_internal pki
vault secrets tune -max-lease-ttl=87600h pki_internal

# Generate root CA certificate
vault write -field=certificate pki_internal/root/generate/internal \
    common_name="Lanmine Internal Root CA" \
    issuer_name="lanmine-root-ca" \
    ttl=87600h > lanmine_internal_ca.crt

# Configure CA and CRL URLs
vault write pki_internal/config/urls \
    issuing_certificates="https://vault.lanmine.local:8200/v1/pki_internal/ca" \
    crl_distribution_points="https://vault.lanmine.local:8200/v1/pki_internal/crl"

# Create role for issuing .lanmine.local certificates
vault write pki_internal/roles/lanmine-local \
    allowed_domains="lanmine.local" \
    allow_subdomains=true \
    max_ttl="720h" \
    key_bits=2048
```

### 2.2 Configure cert-manager ClusterIssuer

**File:** `kubernetes/infrastructure/cert-manager/vault-issuer-internal.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lanmine-internal-ca
spec:
  vault:
    path: pki_internal/sign/lanmine-local
    server: https://10.0.10.21:8200
    caBundle: <base64-encoded-ca-cert>
    auth:
      kubernetes:
        role: cert-manager
        mountPath: /v1/auth/kubernetes
        secretRef:
          name: cert-manager-vault-token
          key: token
```

### 2.3 Distribute CA Certificate to Clients

```bash
# Linux (Debian/Ubuntu)
sudo cp lanmine_internal_ca.crt /usr/local/share/ca-certificates/lanmine-ca.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain lanmine_internal_ca.crt

# Windows (PowerShell as Admin)
certutil -addstore -f "ROOT" lanmine_internal_ca.crt

# Firefox (manual import required)
Preferences → Privacy & Security → Certificates → View Certificates → Authorities → Import
```

## Phase 3: Dual Ingress Configuration

Each Kubernetes service gets TWO ingresses:
1. **External:** `*.hl0.dev` with Let's Encrypt (WAN-dependent)
2. **Internal:** `*.lanmine.local` with Internal CA (WAN-independent)

### Example: Grafana Dual Ingress

**File:** `kubernetes/apps/monitoring/grafana-ingress-internal.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-internal
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: lanmine-internal-ca
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - grafana.lanmine.local
    secretName: grafana-internal-tls
  rules:
  - host: grafana.lanmine.local
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

External ingress (`grafana.hl0.dev`) remains unchanged.

### Services Requiring Dual Ingress

| Service | External | Internal | Priority |
|---------|----------|----------|----------|
| Grafana | grafana.hl0.dev | grafana.lanmine.local | High |
| NetBox | netbox.hl0.dev | netbox.lanmine.local | High |
| ArgoCD | argocd.ts.net | argocd.lanmine.local | High |
| Prometheus | prometheus.ts.net | prometheus.lanmine.local | Medium |
| Alertmanager | alertmanager.ts.net | alertmanager.lanmine.local | Medium |
| Uptime Kuma | uptime.ts.net | uptime.lanmine.local | Low |
| Hubble | hubble.ts.net | hubble.lanmine.local | Low |
| Panda | panda.hl0.dev | panda.lanmine.local | Low |
| Glance | glance.ts.net | glance.lanmine.local | Low |

## Phase 4: Update Monitoring Stack

### 4.1 Update Glance Dashboard

**File:** `kubernetes/apps/glance/configmap.yaml`

Replace all `check-url` with `.lanmine.local` domains:

```yaml
- title: Grafana
  url: https://grafana.hl0.dev
  check-url: https://grafana.lanmine.local  # WAN-resilient
  icon: di:grafana

- title: Vault
  url: https://vault-01.lionfish-caiman.ts.net:8200
  check-url: https://vault.lanmine.local:8200  # WAN-resilient
  icon: di:vault
```

### 4.2 Update Blackbox Exporter Probes

**File:** `kubernetes/apps/monitoring/blackbox-probes.yaml`

```yaml
- job_name: 'blackbox-http'
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        # Internal domains (WAN-resilient)
        - https://grafana.lanmine.local
        - https://netbox.lanmine.local
        - https://argocd.lanmine.local
        - https://prometheus.lanmine.local
        - https://vault.lanmine.local:8200
        - https://authentik.lanmine.local:9443
```

### 4.3 Update Prometheus ServiceMonitors

Replace Tailscale URLs with `.lanmine.local` where applicable.

## Phase 5: Migration Strategy

### Week 1: DNS Foundation (Low Risk)
- [ ] Configure OPNsense Unbound local-zone for `lanmine.local`
- [ ] Add hl0.dev domain override
- [ ] Test DNS resolution from all VLANs
- [ ] Verify existing services still work

### Week 2: Certificate Infrastructure (Medium Risk)
- [ ] Create Vault PKI internal CA
- [ ] Export CA certificate
- [ ] Create cert-manager ClusterIssuer
- [ ] Test certificate issuance
- [ ] Distribute CA cert to 2-3 test clients

### Week 3: Pilot Deployment (Medium Risk)
- [ ] Deploy internal ingress for Grafana
- [ ] Deploy internal ingress for NetBox
- [ ] Test HTTPS access via `.lanmine.local`
- [ ] Verify metrics still collected

### Week 4: Full Rollout (Low Risk)
- [ ] Deploy internal ingresses for all remaining services
- [ ] Update Glance dashboard check-urls
- [ ] Update blackbox probes
- [ ] Distribute CA cert to all clients

### Week 5: Testing & Documentation (Low Risk)
- [ ] Test WAN failure scenario
- [ ] Update CLAUDE.md with new domains
- [ ] Create WAN outage runbook
- [ ] Document CA distribution process

## Testing WAN Failure

### Pre-Test Checklist
- [ ] All internal ingresses deployed
- [ ] CA certificate distributed to test client
- [ ] Glance updated to use `.lanmine.local`
- [ ] Monitoring uses internal domains

### Test Procedure

1. **Baseline:** Verify all services accessible via all three domains
   ```bash
   curl https://grafana.hl0.dev  # Should work
   curl https://grafana.lanmine.local  # Should work
   curl https://grafana.lionfish-caiman.ts.net  # Should work
   ```

2. **Simulate WAN outage:** Disconnect WAN cable or block in OPNsense

3. **Verify internal access still works:**
   ```bash
   curl https://grafana.lanmine.local  # Should work
   curl https://grafana.hl0.dev  # Should work (domain override)
   curl https://grafana.lionfish-caiman.ts.net  # Should FAIL
   ```

4. **Verify DNS resolution:**
   ```bash
   dig grafana.lanmine.local @10.0.10.1  # Returns 10.0.10.40
   dig grafana.hl0.dev @10.0.10.1  # Returns 10.0.10.40
   dig grafana.lionfish-caiman.ts.net @10.0.10.1  # SERVFAIL
   ```

5. **Verify services operational:**
   - Check Grafana dashboards load
   - Check Prometheus scraping
   - Check alerting works
   - Check Glance shows all green

6. **Restore WAN:** Reconnect and verify all three domains work again

### Expected Results

| Domain | WAN Up | WAN Down |
|--------|--------|----------|
| *.lanmine.local | ✅ Works | ✅ Works |
| *.hl0.dev | ✅ Works | ✅ Works (override) |
| *.ts.net | ✅ Works | ❌ Fails |

## Benefits

✅ **Complete WAN independence** - All critical services accessible during internet outage
✅ **Zero downtime migration** - Dual ingress allows gradual transition
✅ **Proper HTTPS everywhere** - Internal CA provides trusted certificates
✅ **Transparent to users** - Services work identically on both domains
✅ **Testing capability** - Can validate infrastructure offline
✅ **Cost reduction** - Reduced Tailscale/Cloudflare dependency

## Maintenance

### DNS Records
- **Management:** Ansible playbook for OPNsense Unbound configuration
- **Sync:** Keep `.lanmine.local` records in sync with Kubernetes ingresses
- **Automation:** Future: Dynamic DNS from Kubernetes ingress controller

### Certificates
- **Internal CA:** 10-year validity, manual renewal
- **Service certificates:** 30-day validity, cert-manager auto-renewal
- **Client trust:** Distribute updated CA cert if root rotated

### Monitoring
- Alert if internal DNS fails to resolve `.lanmine.local`
- Alert if internal CA cannot issue certificates
- Alert if WAN is down (informational, not critical)

## Rollback Plan

If issues arise:
1. Services still accessible via original domains (`.ts.net`, `.hl0.dev`)
2. Remove internal ingresses to reduce complexity
3. Remove OPNsense Unbound custom config
4. Original setup fully intact

No risk of breaking existing access patterns.
