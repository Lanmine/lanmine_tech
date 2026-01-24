# Network Segmentation - VLAN 20 (Contestants)

## Security Issue

**Current State:** VLAN 20 (contestants) has unrestricted access to VLAN 10 (infrastructure)

**Risk:**
- Contestants can access sensitive infrastructure services
- Direct access to Vault (10.0.10.21:8200)
- Direct access to PostgreSQL (10.0.10.23:5432)
- Direct access to Authentik (10.0.10.25:9000)
- Potential for lateral movement or data exfiltration

## Recommended Firewall Rules

### Allow from VLAN 20 to VLAN 10

| Service | Destination | Port | Protocol | Justification |
|---------|-------------|------|----------|---------------|
| DNS | 10.0.10.1 | 53 | UDP | Required for name resolution |
| HTTP/HTTPS (via Traefik) | 10.0.10.40 | 80, 443 | TCP | Access to dashboards (Grafana, etc.) |

### Block from VLAN 20 to VLAN 10

| Service | Destination | Port | Protocol | Reason |
|---------|-------------|------|----------|--------|
| **Vault** | 10.0.10.21 | 8200 | TCP | Secrets management - admin only |
| **PostgreSQL** | 10.0.10.23 | 5432 | TCP | Database - internal only |
| **Authentik** | 10.0.10.25 | 9000, 9443 | TCP | SSO admin interface - staff only |
| **Akvorado** | 10.0.10.26 | 8080 | TCP | NetFlow collector - admin only |
| **n8n** | 10.0.10.27 | 5678 | TCP | Workflow automation - admin only |
| **All other VLAN 10** | 10.0.10.0/24 | * | * | Default deny |

### Services Accessible via Traefik (10.0.10.40)

Contestants can access these dashboards through Traefik ingress:
- Grafana (grafana.lanmine.local or grafana.hl0.dev)
- Uptime Kuma (uptime.lanmine.local)
- Glance (glance.lanmine.local)

Traefik handles authentication/authorization, so contestants only see public dashboards.

## Proposed OPNsense Firewall Configuration

### Rule Order (VLAN 20 Interface)

```
Priority  Action  Source         Destination        Port      Description
────────────────────────────────────────────────────────────────────────────
1         Pass    VLAN20         10.0.10.1          53/UDP    DNS to OPNsense
2         Pass    VLAN20         10.0.10.40         80/TCP    HTTP to Traefik
3         Pass    VLAN20         10.0.10.40         443/TCP   HTTPS to Traefik
4         Block   VLAN20         10.0.10.0/24       *         Block infrastructure
5         Pass    VLAN20         any                *         Allow internet
```

### Configuration via OPNsense Web UI

**Firewall → Rules → VLAN020**

1. **Allow DNS**
   - Action: Pass
   - Interface: VLAN020
   - Protocol: UDP
   - Source: VLAN020 net
   - Destination: 10.0.10.1
   - Destination port: 53
   - Description: "Allow DNS queries to OPNsense"

2. **Allow Traefik HTTP**
   - Action: Pass
   - Interface: VLAN020
   - Protocol: TCP
   - Source: VLAN020 net
   - Destination: 10.0.10.40
   - Destination port: 80
   - Description: "Allow HTTP to Traefik (dashboards)"

3. **Allow Traefik HTTPS**
   - Action: Pass
   - Interface: VLAN020
   - Protocol: TCP
   - Source: VLAN020 net
   - Destination: 10.0.10.40
   - Destination port: 443
   - Description: "Allow HTTPS to Traefik (dashboards)"

4. **Block Infrastructure VLAN**
   - Action: Block
   - Interface: VLAN020
   - Protocol: Any
   - Source: VLAN020 net
   - Destination: 10.0.10.0/24
   - Description: "Block direct access to infrastructure"
   - Log: Yes (for security monitoring)

5. **Allow Internet**
   - Action: Pass
   - Interface: VLAN020
   - Protocol: Any
   - Source: VLAN020 net
   - Destination: any
   - Description: "Allow internet access"

## Alternative: Alias-Based Configuration

Create firewall aliases for easier management:

**Firewall → Aliases**

### Networks
- `VLAN10_Infrastructure`: 10.0.10.0/24
- `VLAN20_Contestants`: 10.0.20.0/23

### Hosts
- `Infrastructure_OPNsense`: 10.0.10.1
- `Infrastructure_Traefik`: 10.0.10.40
- `Infrastructure_Vault`: 10.0.10.21
- `Infrastructure_PostgreSQL`: 10.0.10.23
- `Infrastructure_Authentik`: 10.0.10.25

### Port Groups
- `Traefik_Ports`: 80, 443
- `DNS_Port`: 53

Then use these aliases in rules for cleaner configuration.

## Monitoring and Alerting

### Log Analysis

Monitor blocked connection attempts:
```bash
# View firewall blocks in real-time
ssh root@10.0.10.1 'clog /var/log/filter.log | grep -i block'
```

### Prometheus Alert

Create alert for suspicious VLAN 20 → VLAN 10 traffic:

```yaml
- name: network_security
  rules:
  - alert: VLAN20InfrastructureAccess
    expr: rate(firewall_blocked_packets{src_vlan="20",dst_vlan="10"}[5m]) > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High rate of blocked packets from VLAN 20 to infrastructure"
      description: "Contestants may be scanning infrastructure network"
```

## Testing the Rules

### Before Applying Rules

Test current access from a VLAN 20 client:
```bash
# Should succeed (currently no restrictions)
curl -k https://10.0.10.21:8200/v1/sys/health
curl http://10.0.10.23:5432  # Should connect to PostgreSQL
```

### After Applying Rules

Test restricted access:
```bash
# Should timeout/be blocked
curl -k --max-time 5 https://10.0.10.21:8200/v1/sys/health  # Vault blocked
curl --max-time 5 http://10.0.10.23:5432  # PostgreSQL blocked

# Should succeed
dig @10.0.10.1 grafana.lanmine.local  # DNS allowed
curl https://10.0.10.40  # Traefik allowed
curl https://grafana.lanmine.local  # Dashboard via Traefik allowed
```

## Rollback Plan

If firewall rules cause issues:

1. **Via Web UI:** Disable the blocking rule temporarily
2. **Via SSH:**
   ```bash
   ssh root@10.0.10.1
   pfctl -d  # Disable firewall (emergency only!)
   ```
3. **Via Console:** Physical access to OPNsense console

## Additional Security Layers

### 1. Traefik Middlewares

Add authentication to dashboards:
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: contestant-auth
spec:
  basicAuth:
    secret: contestant-credentials
```

### 2. Network Policies (Kubernetes)

Restrict pod-to-pod communication:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-vlan20
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.10.0/24  # Only allow from infrastructure VLAN
```

### 3. VPN Access for Admins

Staff access to infrastructure services via Tailscale:
- Vault: https://vault-01.lionfish-caiman.ts.net:8200
- Authentik: https://authentik.lionfish-caiman.ts.net:9000
- Bypass VLAN restrictions entirely

## Implementation Steps

1. **Backup current firewall config** (OPNsense Web UI → System → Configuration → Backups)
2. **Create aliases** for cleaner rules
3. **Add rules in order** (DNS, Traefik, Block, Allow Internet)
4. **Test from VLAN 20 client** before event
5. **Monitor logs** during event for blocked attempts
6. **Document any exceptions** needed during event

## Future Enhancements

1. **VLAN 30 (OOB/iDRAC):** Similar restrictions to VLAN 20
2. **Rate Limiting:** Limit DNS queries per IP to prevent abuse
3. **IDS/IPS:** Deploy Suricata on OPNsense for threat detection
4. **802.1X:** Port-based authentication for switch access
5. **VLAN Tagging:** Dynamic VLAN assignment based on device type
