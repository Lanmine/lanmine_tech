# TACACS+ Authentication via Authentik - Design Document

**Date:** 2026-01-24
**Goal:** Centralized user management for network switches using TACACS+ and Authentik LDAP

## Overview

Replace local switch authentication with centralized TACACS+ authentication backed by Authentik LDAP. This enables single-point user management - add/remove network engineers in Authentik UI, and access to all switches updates immediately.

## Architecture

### Components

1. **Authentik LDAP Outpost** (Kubernetes, authentik namespace)
   - Exposes LDAP interface on port 389
   - Serves user/group data from Authentik database
   - Base DN: `dc=ldap,dc=lanmine,dc=no`
   - Bind DN: `cn=ldap-bind,dc=ldap,dc=lanmine,dc=no`

2. **TACACS+ Server** (Kubernetes, new tacacs namespace)
   - Image: `lfkeitel/tacacs_plus:latest`
   - Port: 49/TCP (TACACS+ standard)
   - LoadBalancer IP from MetalLB (10.0.10.X)
   - ConfigMap for tacacs.conf
   - Secret for shared key + LDAP bind password

3. **Network Switches** (Cisco IOS)
   - AAA configured to use TACACS+ server
   - Shared secret authentication
   - Fallback to local admin account

### Network Flow

```
User SSH → Switch (10.0.99.101)
            ↓
        TACACS+ query (port 49, shared secret)
            ↓
        TACACS+ Pod (10.0.10.X via LoadBalancer)
            ↓
        LDAP query (port 389, bind DN)
            ↓
        Authentik LDAP Outpost (authentik-ldap.authentik.svc:389)
            ↓
        Authentik Server (authentik-server.authentik.svc:9000)
```

## User & Group Management

### Authentik Groups → Switch Privilege Levels

| Authentik Group | TACACS Privilege | Access Level |
|----------------|------------------|--------------|
| network-admins | 15 | Full config access, enable mode, reload |
| network-operators | 7 | Read-only, show commands, ping, traceroute |
| network-readonly | 1 | Very limited, basic show commands only |

### User Lifecycle

1. **Add User:** Create in Authentik UI → Add to group → Immediate switch access
2. **Change Role:** Move between groups → Privilege level updates on next login
3. **Remove User:** Delete from Authentik or remove from groups → Access revoked immediately
4. **Emergency Access:** Local admin account always available if TACACS+ unreachable

## TACACS+ Configuration

### tacacs.conf (via ConfigMap)

```ini
accounting file = /var/log/tacacs/accounting.log

# LDAP authentication backend
default authentication = ldap

authentication ldap {
    host = authentik-ldap.authentik.svc.cluster.local
    port = 389
    bind_dn = cn=ldap-bind,dc=ldap,dc=lanmine,dc=no
    bind_password = <from-vault-secret>
    base_dn = dc=ldap,dc=lanmine,dc=no
    user_filter = (&(objectClass=inetOrgPerson)(uid=%s))
    group_filter = (&(objectClass=groupOfNames)(member=%s))
}

# Group to privilege mappings
group network-admins {
    default service = permit
    service = exec {
        priv-lvl = 15
    }
}

group network-operators {
    default service = permit
    service = exec {
        priv-lvl = 7
    }
}

group network-readonly {
    default service = permit
    service = exec {
        priv-lvl = 1
    }
}

# Device access control
device 10.0.99.0/24 {
    key = <from-vault-secret>
}
```

### Secrets (Vault: secret/infrastructure/tacacs)

- `ldap_bind_password` - LDAP service account password
- `tacacs_shared_key` - Shared secret between switches and TACACS+ server

## Switch Configuration

### AAA Configuration (via Ansible)

```ios
! Enable AAA
aaa new-model

! TACACS+ server
tacacs-server host 10.0.10.X
tacacs-server key <shared-secret>

! Authentication: TACACS+ first, local fallback
aaa authentication login default group tacacs+ local
aaa authentication enable default group tacacs+ enable

! Authorization: TACACS+ determines privilege level
aaa authorization exec default group tacacs+ local
aaa authorization commands 15 default group tacacs+ local

! Accounting: Log all commands
aaa accounting exec default start-stop group tacacs+
aaa accounting commands 15 default start-stop group tacacs+

! Local admin fallback (emergency access)
username admin privilege 15 secret <from-vault>
```

## Kubernetes Resources

### Namespace
- `tacacs` (new)

### Deployment
- Name: `tacacs-server`
- Replicas: 2 (HA with session affinity)
- Container: `lfkeitel/tacacs_plus:latest`
- Port: 49/TCP
- Liveness probe: TCP socket on port 49
- Resources: 100m CPU, 128Mi memory

### Service
- Type: LoadBalancer (MetalLB)
- Port: 49/TCP
- Session affinity: ClientIP (TACACS+ is stateful)

### ConfigMap
- Name: `tacacs-config`
- Data: tacacs.conf

### Secret
- Name: `tacacs-secrets`
- Source: Vault `secret/infrastructure/tacacs`
- Keys: `ldap_bind_password`, `tacacs_shared_key`

## Testing Plan

1. **Deploy TACACS+ server** - Apply Kubernetes manifests, verify LoadBalancer IP assigned
2. **Configure Authentik LDAP** - Create outpost, bind account, test LDAP query
3. **Create test user** - Username: `nettest`, Group: `network-readonly` (priv 1)
4. **Configure mgmt-sw-01** - Run Ansible playbook to enable AAA
5. **Test read-only access** - SSH as nettest, verify `show` commands work, `config` denied
6. **Promote user** - Move nettest to `network-admins` group
7. **Test full access** - SSH as nettest, verify privilege 15, config mode accessible
8. **Test fallback** - Stop TACACS+ pods, verify local admin login still works
9. **Restore TACACS+** - Start pods, verify TACACS+ login resumes

## Monitoring & Observability

### Metrics (Prometheus)
- TACACS+ server exposes metrics on port 9090
- Metrics: auth_attempts_total, auth_failures_total, active_sessions

### Logging (Loki)
- JSON logs to stdout → captured by Loki
- Fields: username, source_ip, privilege_level, command, timestamp

### Grafana Dashboard
- Panel: Authentication attempts/failures (time series)
- Panel: Active sessions by user (table)
- Panel: Failed login attempts by IP (bar chart)
- Panel: Commands executed (logs)

### Alerts
- `TACACSServerDown` - No TACACS+ pods running (critical)
- `TACACSHighFailureRate` - >10 failures in 5 min (warning)
- `TACACSNoAuthentications` - No auth attempts in 24h (info, might be normal)

## Rollout Strategy

### Phase 1: Development & Testing
1. Deploy TACACS+ to Kubernetes (dev namespace first)
2. Configure Authentik LDAP outpost
3. Test with single switch (mgmt-sw-01)
4. Create test users in all privilege groups
5. Verify authentication, authorization, accounting

### Phase 2: Production Deployment
1. Deploy TACACS+ to production tacacs namespace
2. Configure production Authentik groups
3. Migrate mgmt-sw-01 to production TACACS+
4. Monitor for 48 hours

### Phase 3: Scale to Fleet
1. Update Ansible inventory for all switches
2. Run configure-tacacs.yml playbook on all switches
3. Verify each switch can authenticate
4. Document user onboarding process

## Rollback Plan

If issues occur:
1. SSH to switch using local admin account
2. Remove AAA configuration: `no aaa new-model`
3. Revert to local authentication only
4. Investigate TACACS+ logs for root cause

## Security Considerations

- **Shared Secret** - Strong random key (32+ chars), stored in Vault only
- **LDAP Bind Account** - Read-only service account, minimal permissions
- **Local Fallback** - Admin account preserved for emergency access
- **Encryption** - TACACS+ supports encryption of entire packet (not just password)
- **Audit Logging** - All commands logged to TACACS+ accounting file

## Future Enhancements

- **Multi-site** - Deploy regional TACACS+ servers for redundancy
- **MFA** - Authentik supports OTP, could integrate with TACACS+
- **Command Authorization** - Restrict specific commands per group
- **Session Recording** - Capture full CLI sessions for forensics
- **RADIUS** - Add RADIUS for WiFi/VPN authentication (same Authentik backend)

## Success Criteria

✅ New user added in Authentik can immediately SSH to switches
✅ User privilege level controlled by Authentik group membership
✅ All switch commands logged to TACACS+ accounting
✅ Local admin fallback works when TACACS+ unavailable
✅ Prometheus metrics and Grafana dashboard operational
✅ Zero service disruption during rollout
