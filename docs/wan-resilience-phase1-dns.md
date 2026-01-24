# WAN Resilience - Phase 1: DNS Foundation

## Overview

Phase 1 establishes WAN-independent DNS resolution by:
1. Configuring OPNsense Unbound as authoritative for `lanmine.local`
2. Adding domain override for `hl0.dev` → Traefik LoadBalancer
3. Testing DNS resolution from all VLANs

**Risk Level:** Low (zero impact on existing services)

## Prerequisites

- Ansible control node with Vault access
- SSH access to OPNsense (root)
- `dig` utility for DNS testing

## Step 1: Configure OPNsense DNS

### Automated Configuration (Recommended)

```bash
cd /home/ubuntu-mgmt01/infra/lanmine_tech/ansible

# Configure lanmine.local domain
ansible-playbook playbooks/configure-opnsense-dns.yml
```

This playbook:
- ✓ Generates Unbound custom configuration
- ✓ Deploys configuration to OPNsense
- ✓ Restarts Unbound service
- ✓ Verifies configuration syntax
- ✓ Tests DNS resolution

### Manual Configuration (Fallback)

If automated deployment fails, configure manually:

**1. SSH to OPNsense:**
```bash
ssh root@10.0.10.1
```

**2. Create custom Unbound config:**
```bash
cat > /var/unbound/unbound.conf.d/lanmine-local.conf << 'EOF'
server:
  # Local domain authority for lanmine.local
  local-zone: "lanmine.local." static

  # Infrastructure VMs
  local-data: "vault.lanmine.local. IN A 10.0.10.21"
  local-data: "postgres.lanmine.local. IN A 10.0.10.23"
  local-data: "authentik.lanmine.local. IN A 10.0.10.25"
  local-data: "akvorado.lanmine.local. IN A 10.0.10.26"
  local-data: "n8n.lanmine.local. IN A 10.0.10.27"
  local-data: "proxmox.lanmine.local. IN A 10.0.10.5"
  local-data: "opnsense.lanmine.local. IN A 10.0.10.1"

  # Kubernetes services (via Traefik)
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

  # Reverse DNS
  local-data-ptr: "10.0.10.21 vault.lanmine.local"
  local-data-ptr: "10.0.10.23 postgres.lanmine.local"
  local-data-ptr: "10.0.10.25 authentik.lanmine.local"
  local-data-ptr: "10.0.10.26 akvorado.lanmine.local"
  local-data-ptr: "10.0.10.27 n8n.lanmine.local"
  local-data-ptr: "10.0.10.5 proxmox.lanmine.local"
  local-data-ptr: "10.0.10.1 opnsense.lanmine.local"
  local-data-ptr: "10.0.10.40 grafana.lanmine.local"
EOF
```

**3. Verify syntax:**
```bash
unbound-checkconf
```

**4. Restart Unbound:**
```bash
/usr/local/etc/rc.d/unbound restart
```

## Step 2: Configure hl0.dev Domain Override

**NOTE:** This step currently requires manual configuration in OPNsense UI.

### Via Web UI

1. Navigate to: **Services → Unbound DNS → Query Forwarding**

2. Click **+** to add domain override

3. Configure:
   - **Domain:** `hl0.dev`
   - **Server IP:** `10.0.10.40`
   - **Description:** `Cloudflare domain override (WAN-resilient)`

4. Click **Save**

5. Click **Apply Changes**

### Future: API Automation

OPNsense API endpoint for domain overrides:
```bash
curl -k -X POST \
  -H "Content-Type: application/json" \
  -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  -d '{"domain":"hl0.dev","server":"10.0.10.40"}' \
  https://10.0.10.1/api/unbound/settings/addDomainOverride
```

## Step 3: Test DNS Resolution

### Automated Testing

```bash
cd /home/ubuntu-mgmt01/infra/lanmine_tech/ansible

# Run comprehensive DNS tests
ansible-playbook playbooks/test-dns-resolution.yml
```

Expected output:
```
✓ PASSED (10):
  - grafana.lanmine.local
  - vault.lanmine.local
  - netbox.lanmine.local
  - authentik.lanmine.local
  - grafana.hl0.dev
  - netbox.hl0.dev
  ...

⚠ OPTIONAL FAILED (1):
  - grafana.lionfish-caiman.ts.net (WAN-dependent, expected to fail without WAN)

Status: PASS
```

### Manual Testing

From any host on the network:

```bash
# Test lanmine.local domain
dig grafana.lanmine.local @10.0.10.1
# Should return: 10.0.10.40

dig vault.lanmine.local @10.0.10.1
# Should return: 10.0.10.21

# Test hl0.dev override
dig grafana.hl0.dev @10.0.10.1
# Should return: 10.0.10.40

# Test reverse DNS
dig -x 10.0.10.40 @10.0.10.1
# Should return: grafana.lanmine.local

# Browser test
curl -I https://grafana.lanmine.local
# Should fail (no certificate yet) but DNS should resolve
```

## Step 4: Test from Different VLANs

### VLAN 10 (Infrastructure)
```bash
# From any VLAN 10 host (vault-01, postgres-01, etc.)
dig grafana.lanmine.local
```

### VLAN 20 (Contestants)
```bash
# From VLAN 20 host (if available)
dig grafana.lanmine.local
```

### VLAN 99 (Management)
```bash
# From ubuntu-mgmt01
dig grafana.lanmine.local
```

All should resolve to correct IPs using OPNsense as resolver.

## Verification Checklist

- [ ] Unbound configuration deployed successfully
- [ ] Unbound service restarted without errors
- [ ] `lanmine.local` domain resolves (10+ records)
- [ ] `hl0.dev` domain override configured
- [ ] `hl0.dev` domains resolve to 10.0.10.40
- [ ] Reverse DNS works for key IPs
- [ ] Resolution works from VLAN 10
- [ ] Resolution works from VLAN 20 (if applicable)
- [ ] Resolution works from VLAN 99
- [ ] Existing services still work via original domains

## Rollback

If issues arise:

**1. Remove custom Unbound config:**
```bash
ssh root@10.0.10.1
rm /var/unbound/unbound.conf.d/lanmine-local.conf
/usr/local/etc/rc.d/unbound restart
```

**2. Remove domain override via UI:**
- Services → Unbound DNS → Query Forwarding
- Delete `hl0.dev` override
- Apply Changes

**3. Verify original services still work**

## Next Steps

After successful Phase 1 completion:

**Phase 2:** Internal Certificate Authority
- Deploy Vault PKI for `*.lanmine.local` certificates
- Configure cert-manager ClusterIssuer
- Issue test certificate

See: `docs/wan-resilience-plan.md` for complete roadmap

## Troubleshooting

### DNS Not Resolving

**Check Unbound status:**
```bash
ssh root@10.0.10.1
/usr/local/etc/rc.d/unbound status
```

**Check Unbound logs:**
```bash
ssh root@10.0.10.1
tail -f /var/log/resolver.log
```

**Verify configuration syntax:**
```bash
ssh root@10.0.10.1
unbound-checkconf
```

### Domain Override Not Working

**Verify override configured:**
```bash
ssh root@10.0.10.1
cat /var/unbound/domainoverrides.conf
```

Should contain:
```
forward-zone:
  name: "hl0.dev"
  forward-addr: 10.0.10.40
```

### Resolution Works from CLI but Not Browser

**Check client DNS configuration:**
```bash
# Linux/Mac
cat /etc/resolv.conf
# Should show: nameserver 10.0.10.1

# Windows
ipconfig /all
# DNS Servers should show: 10.0.10.1
```

**Flush DNS cache:**
```bash
# Linux
sudo systemd-resolve --flush-caches

# Mac
sudo dscacheutil -flushcache

# Windows
ipconfig /flushdns
```

## Success Criteria

Phase 1 is complete when:

✅ All `*.lanmine.local` domains resolve correctly
✅ `*.hl0.dev` domains resolve to Traefik (10.0.10.40)
✅ DNS works from all VLANs
✅ Existing services unchanged
✅ DNS tests pass with 100% success rate (excluding optional WAN-dependent tests)

**Ready for Phase 2: Internal Certificate Authority**
