# LANcache DNS Architecture

## Overview

LANcache is a caching proxy for game downloads that intercepts DNS queries for game CDN domains (Steam, Epic Games, Battle.net, etc.) and serves cached content from a local server.

## Network Architecture

**Location:** Physical Dell R630 server on VLAN 20 (Contestants)
- **IP:** 10.0.20.2
- **Interface:** Bond0 (2x 10G LACP)
- **VLAN:** 20 (10.0.20.0/23)

## DNS Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ VLAN 20 Clients (LAN Contestants)                              │
│ DHCP assigns DNS: 10.0.20.2                                     │
└────────────────────┬────────────────────────────────────────────┘
                     │ All DNS queries
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ LANcache-DNS Container (10.0.20.2:53)                          │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Intercept CDN Domains                                       │ │
│ │ ├─ *.cdn.steampowered.com → 10.0.20.2                      │ │
│ │ ├─ *.epicgames.com → 10.0.20.2                             │ │
│ │ ├─ *.blizzard.com → 10.0.20.2                              │ │
│ │ └─ ... (100+ CDN domains)                                  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Forward All Other Domains                                   │ │
│ │ └─ UPSTREAM_DNS → 10.0.10.1 (OPNsense)                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
└────────────────────┬────────────────────────────────────────────┘
                     │ Non-CDN queries
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ OPNsense Unbound DNS (10.0.10.1)                               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Local Zones                                                 │ │
│ │ ├─ *.lanmine.local → Local A records (WAN-resilient)       │ │
│ │ └─ *.hl0.dev → Wildcard to 10.0.10.40 (WAN-resilient)      │ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Upstream Forwarding                                         │ │
│ │ └─ Internet domains → Cloudflare (1.1.1.1) or WAN          │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration

### DHCP (OPNsense Kea)

VLAN 20 clients receive:
- **IP Range:** 10.0.20.5 - 10.0.21.254
- **Gateway:** 10.0.20.1 (OPNsense)
- **DNS:** 10.0.20.2 (LANcache)

### LANcache Docker Compose

```yaml
lancache-dns:
  image: lancachenet/lancache-dns:latest
  environment:
    - UPSTREAM_DNS=10.0.10.1       # OPNsense (WAN-resilient)
    - USE_GENERIC_CACHE=true
    - LANCACHE_IP=10.0.20.2
  ports:
    - "10.0.20.2:53:53/udp"
```

**Why OPNsense as Upstream:**
- ✅ Resolves .lanmine.local domains (monitoring, dashboards)
- ✅ Resolves .hl0.dev wildcard (Cloudflare services)
- ✅ Works during WAN outages (internal DNS)
- ✅ Centralized DNS policy and logging

**Previous Configuration (8.8.8.8):**
- ❌ Can't resolve .lanmine.local
- ❌ Fails during WAN outages
- ❌ Bypasses internal DNS policies

## DNS Query Examples

### Game Download (CDN Domain)

```
Client: Steam wants to download game from cdn.steampowered.com
  ↓
LANcache-DNS: Intercept! Return 10.0.20.2
  ↓
Client: Connect to 10.0.20.2:443
  ↓
LANcache-Monolithic: Serve cached content or download and cache
```

### Internal Service Access

```
Client: Browser wants grafana.lanmine.local
  ↓
LANcache-DNS: Not a CDN domain, forward to 10.0.10.1
  ↓
OPNsense: Local zone lookup → 10.0.10.40
  ↓
Client: Connect to 10.0.10.40 (Traefik)
```

### External Website

```
Client: Browser wants youtube.com
  ↓
LANcache-DNS: Not a CDN domain, forward to 10.0.10.1
  ↓
OPNsense: Not local, forward to 1.1.1.1
  ↓
Cloudflare: Resolve youtube.com
  ↓
Client: Connect to YouTube
```

## WAN Resilience

During WAN outage:
- ✅ Game downloads continue (cached content)
- ✅ Internal services accessible (.lanmine.local, .hl0.dev)
- ❌ New game downloads fail (no upstream)
- ❌ External websites fail (no internet)

## Monitoring

**LANcache Metrics (Prometheus):**
- Endpoint: http://10.0.20.2:9113/metrics
- Exporter: nginx-prometheus-exporter
- Metrics: Cache hits, bandwidth saved, storage usage

**ServiceMonitor:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: lancache-metrics
  namespace: monitoring
spec:
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
  selector:
    matchLabels:
      app: lancache-exporter
```

## Cache Management

**Cache Location:** `/cache/data` on lancache server
**Max Size:** 10 TB (configured via `CACHE_DISK_SIZE`)
**Retention:** 3650 days (10 years)

**Supported Services:**
- Steam
- Epic Games Store
- Origin (EA)
- Uplay (Ubisoft)
- Battle.net (Blizzard)
- Windows Update
- And 100+ more CDNs

## Troubleshooting

### DNS Not Intercepting

**Check lancache-dns container:**
```bash
ssh ubuntu@10.0.20.2
docker logs lancache-dns
```

**Test CDN domain resolution:**
```bash
dig @10.0.20.2 cdn.steampowered.com
# Should return: 10.0.20.2
```

### Cache Not Working

**Check lancache-monolithic container:**
```bash
docker logs lancache-monolithic
```

**Check nginx access logs:**
```bash
tail -f /cache/logs/access.log
```

**Verify cache storage:**
```bash
df -h /cache
du -sh /cache/data
```

### Internal Services Not Resolving

**Test .lanmine.local resolution from VLAN 20 client:**
```bash
dig @10.0.20.2 grafana.lanmine.local
# Should return: 10.0.10.40
```

**Check upstream DNS setting:**
```bash
docker inspect lancache-dns | grep UPSTREAM_DNS
# Should show: 10.0.10.1
```

**Test OPNsense DNS directly:**
```bash
dig @10.0.10.1 grafana.lanmine.local
# Should return: 10.0.10.40
```

## Security Considerations

1. **VLAN Isolation:** VLAN 20 isolated from infrastructure (VLAN 10)
2. **DNS Interception:** Only for known game CDN domains
3. **HTTPS Passthrough:** LANcache uses SNI proxy for HTTPS (no certificate interception)
4. **Cache Storage:** Local only, no sensitive data cached

## Deployment

**Ansible Playbook:**
```bash
cd ansible
ansible-playbook playbooks/deploy-lancache.yml
```

**Manual Docker Compose:**
```bash
ssh ubuntu@10.0.20.2
cd /opt/lancache
docker compose up -d
```

## Network Bonding (802.3ad LACP)

LANcache uses bonded 10G interfaces for high throughput:

```yaml
# /etc/netplan/01-lancache.yaml
bonds:
  bond0:
    interfaces: [eno49, eno50]
    parameters:
      mode: 802.3ad
      lacp-rate: fast
      transmit-hash-policy: layer3+4
```

**Bandwidth Capacity:**
- 2x 10G interfaces = 20 Gbps aggregate
- Typical game download: 1-10 Gbps during LAN events

## Future Enhancements

1. **Redundant LANcache:** Second server for failover
2. **Geographic Distribution:** Multiple cache nodes per LAN segment
3. **Pre-warming:** Download popular games before event
4. **Analytics Dashboard:** Real-time cache hit rates and bandwidth savings
