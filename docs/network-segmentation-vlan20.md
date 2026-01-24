# Network Segmentation - VLAN 20 (Contestants)

## Security Issue

**Current State:** VLAN 20 (contestants) has unrestricted access to VLAN 10 (infrastructure)

**Risk:**
- Contestants can access sensitive infrastructure services
- Direct access to Vault (10.0.10.21:8200)
- Direct access to PostgreSQL (10.0.10.23:5432)
- Direct access to Authentik (10.0.10.25:9000)
- Potential for lateral movement or data exfiltration

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ VLAN 20 Clients (10.0.20.x)                                │
│ - Gateway: 10.0.20.1 (OPNsense)                            │
│ - DNS: 10.0.20.2 (LANcache)                                │
└────────────────┬────────────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
┌──────────────┐   ┌─────────────────────────┐
│  LANcache    │   │  Internet               │
│  10.0.20.2   │   │  (via 10.0.20.1)        │
│              │   │                         │
│  Needs:      │   └─────────────────────────┘
│  DNS → 10.0.10.1:53                        │
└──────────────┘
```

## Key Insight

**OPNsense already has an interface on VLAN 20 (10.0.20.1)**

This means:
- Contestants don't need to reach VLAN 10 at all
- LANcache is on the same VLAN as contestants
- Only LANcache needs to query OPNsense DNS on VLAN 10

## What Contestants Actually Need

| Resource | Location | Access Method |
|----------|----------|---------------|
| Game downloads | LANcache (10.0.20.2) | Same VLAN ✅ |
| Internet (YouTube, Discord) | OPNsense gateway (10.0.20.1) | Same VLAN ✅ |
| DNS resolution | LANcache (10.0.20.2) | Same VLAN ✅ |
| **Infrastructure dashboards** | **VLAN 10** | **NOT NEEDED** ❌ |

Contestants don't need Grafana, NetBox, or monitoring - that's for staff only.

## Simplified Firewall Rules

### OPNsense VLAN020 Interface Rules

```
Priority  Action  Source         Destination        Port      Description
─────────────────────────────────────────────────────────────────────────────
1         Pass    10.0.20.2      10.0.10.1          53/UDP    LANcache DNS upstream
2         Block   VLAN20 net     10.0.10.0/24       *         Block infrastructure access
3         Pass    VLAN20 net     any                *         Allow internet
```

## Configuration via OPNsense Web UI

**Firewall → Rules → VLAN020**

### Rule 1: Allow LANcache DNS Queries

- **Action:** Pass
- **Interface:** VLAN020
- **Protocol:** UDP
- **Source:** Single host: `10.0.20.2`
- **Destination:** Single host: `10.0.10.1`
- **Destination port:** 53
- **Description:** "LANcache DNS upstream to OPNsense"

### Rule 2: Block Infrastructure VLAN

- **Action:** Block
- **Interface:** VLAN020
- **Protocol:** Any
- **Source:** VLAN020 net
- **Destination:** 10.0.10.0/24
- **Description:** "Block contestant access to infrastructure"
- **Log:** Yes (for security monitoring)

### Rule 3: Allow Internet Access

- **Action:** Pass
- **Interface:** VLAN020
- **Protocol:** Any
- **Source:** VLAN020 net
- **Destination:** any
- **Description:** "Allow internet access"

## Traffic Flows After Rules

### Game Download (Works)

```
Contestant → Steam CDN query
  ↓ DNS to 10.0.20.2
LANcache-DNS → Intercept, return 10.0.20.2
  ↓
Contestant → Download from 10.0.20.2:80/443
  ↓
LANcache → Serve cached content
```

### Internet Website (Works)

```
Contestant → youtube.com query
  ↓ DNS to 10.0.20.2
LANcache-DNS → Not a CDN, forward to 10.0.10.1 ✅ (Rule 1 allows)
  ↓
OPNsense → Resolve via Cloudflare
  ↓
Contestant → Connect to YouTube via gateway 10.0.20.1
```

### Infrastructure Access Attempt (Blocked)

```
Contestant → Try to access vault.lanmine.local
  ↓ DNS to 10.0.20.2
LANcache-DNS → Forward to 10.0.10.1, get 10.0.10.21
  ↓
Contestant → Try HTTPS to 10.0.10.21:8200
  ❌ BLOCKED by Rule 2 (destination 10.0.10.0/24)
```

## What Gets Blocked

All direct access from VLAN 20 clients to VLAN 10:

| Service | IP | Port | Impact |
|---------|-----|------|--------|
| Vault | 10.0.10.21 | 8200 | ❌ Blocked |
| PostgreSQL | 10.0.10.23 | 5432 | ❌ Blocked |
| Authentik | 10.0.10.25 | 9000 | ❌ Blocked |
| Akvorado | 10.0.10.26 | 8080 | ❌ Blocked |
| n8n | 10.0.10.27 | 5678 | ❌ Blocked |
| Kubernetes services | 10.0.10.40 | 80, 443 | ❌ Blocked |
| **All VLAN 10** | 10.0.10.0/24 | * | ❌ Blocked |

**Exception:** LANcache (10.0.20.2) can still query OPNsense DNS (10.0.10.1:53)

## Staff Access to Infrastructure

Staff should use Tailscale VPN to access infrastructure services:

- Grafana: https://grafana.lionfish-caiman.ts.net
- Vault: https://vault-01.lionfish-caiman.ts.net:8200
- NetBox: https://netbox.lionfish-caiman.ts.net
- Completely bypasses VLAN restrictions

Or connect from VLAN 10 management network.

## Testing the Rules

### Before Applying (Current State)

From a VLAN 20 client:

```bash
# Currently works (should be blocked)
curl -k https://10.0.10.21:8200/v1/sys/health
telnet 10.0.10.23 5432
```

### After Applying Rules

From a VLAN 20 client:

```bash
# Should timeout/be blocked
curl -k --max-time 5 https://10.0.10.21:8200  # Vault blocked
telnet 10.0.10.23 5432  # PostgreSQL blocked
curl --max-time 5 http://10.0.10.40  # Traefik blocked

# Should work
ping 10.0.20.2  # LANcache (same VLAN)
dig @10.0.20.2 steampowered.com  # DNS via LANcache
curl https://youtube.com  # Internet access
```

### From LANcache Server

```bash
ssh ubuntu@10.0.20.2
dig @10.0.10.1 vault.lanmine.local  # Should work (Rule 1)
```

## Monitoring

### View Blocked Connection Attempts

```bash
# SSH to OPNsense
ssh root@10.0.10.1

# View firewall logs
clog /var/log/filter.log | grep -i block | grep "10.0.20"
```

### Expected Log Entries

```
Jan 24 13:00:00 filterlog: 5,,,1000000103,igb2,match,block,in,4,0x0,,64,12345,0,none,6,tcp,60,10.0.20.50,10.0.10.21,54321,8200,0,S,1234567890,,64240,,mss
```

This shows a blocked attempt from 10.0.20.50 trying to reach 10.0.10.21:8200 (Vault).

### Prometheus Alert

```yaml
- name: network_security
  rules:
  - alert: ContestantInfrastructureAccess
    expr: rate(firewall_blocked_packets{src_vlan="20",dst_net="10.0.10.0/24"}[5m]) > 5
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Contestants attempting to access infrastructure VLAN"
      description: "High rate of blocked packets from VLAN 20 to VLAN 10"
```

## Rollback Plan

If rules cause issues:

### Via Web UI
1. Navigate to **Firewall → Rules → VLAN020**
2. Disable the blocking rule (Rule 2)
3. Click **Apply Changes**

### Via SSH (Emergency)
```bash
ssh root@10.0.10.1
pfctl -d  # Disable packet filter (EMERGENCY ONLY)
configctl filter reload  # Reload with original rules
```

### Via Console
Physical access to OPNsense console to disable firewall

## Alternative: Per-Service Blocking

Instead of blocking entire VLAN 10, block specific services:

```
1. Block 10.0.10.21:8200 (Vault)
2. Block 10.0.10.23:5432 (PostgreSQL)
3. Block 10.0.10.25:9000,9443 (Authentik)
4. Block 10.0.10.26:8080 (Akvorado)
5. Block 10.0.10.27:5678 (n8n)
6. Allow rest
```

**Not recommended:** More complex, easy to miss a service, default-deny is more secure.

## Implementation Checklist

- [ ] Backup OPNsense config (**System → Configuration → Backups**)
- [ ] Take screenshot of current VLAN020 rules (for rollback reference)
- [ ] Add Rule 1: Allow LANcache DNS (10.0.20.2 → 10.0.10.1:53)
- [ ] Add Rule 2: Block VLAN 10 access (VLAN20 net → 10.0.10.0/24)
- [ ] Add Rule 3: Allow internet (VLAN20 net → any)
- [ ] Apply changes
- [ ] Test from VLAN 20 client (ping, DNS, game download, infrastructure block)
- [ ] Monitor logs during first hour
- [ ] Document any issues or exceptions needed

## Additional Security Measures

### 1. Rate Limiting (DNS)

Prevent DNS amplification attacks:
```
Services → Unbound DNS → Advanced
  Rate Limiting: 1000 queries/second per IP
```

### 2. Private RFC1918 Blocking

Prevent contestants from spoofing private IPs:
```
Firewall → Rules → VLAN020
  Block source: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
  (except VLAN 20 subnet)
```

### 3. Egress Filtering

Block outbound traffic to bogon networks:
```
Firewall → Rules → VLAN020
  Block destination: RFC1918, Multicast, Reserved
```

### 4. MAC Address Filtering (Optional)

For high-security events, whitelist known MAC addresses:
```
Services → DHCPv4 → [VLAN020]
  Deny unknown clients: Yes
```

## Future Enhancements

1. **VLAN 30 Isolation:** Apply same rules to OOB/iDRAC VLAN
2. **IDS/IPS:** Deploy Suricata on OPNsense
3. **802.1X:** Port-based authentication on switches
4. **Honeypot:** Deploy fake services on VLAN 10 to detect scanning
5. **Automatic Blocking:** Auto-block IPs with >100 blocked attempts

## Summary

**Simple 3-Rule Firewall:**
1. ✅ Allow LANcache → OPNsense DNS (10.0.20.2 → 10.0.10.1:53)
2. ❌ Block all VLAN 20 → VLAN 10 (10.0.20.0/23 → 10.0.10.0/24)
3. ✅ Allow internet access (VLAN 20 → any)

**Result:**
- Contestants get game downloads and internet
- Infrastructure protected from contestant access
- LANcache can still resolve domains via OPNsense
- Simple to understand, audit, and maintain
