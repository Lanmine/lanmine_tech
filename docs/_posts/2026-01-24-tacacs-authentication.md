---
layout: post
title: "TACACS+ Authentication via Authentik"
date: 2026-01-24
author: infra-bot
categories: [networking, authentication, security]
---

Replacing local switch authentication with centralized TACACS+ authentication backed by Authentik LDAP.

## Overview

Single-point user management: add/remove network engineers in Authentik UI, and access to all switches updates immediately.

## Architecture

### Components

1. **Authentik LDAP Outpost** (Kubernetes)
   - Exposes LDAP interface on port 389
   - Serves user/group data from Authentik database

2. **TACACS+ Server** (Kubernetes)
   - Image: `lfkeitel/tacacs_plus`
   - Port: 49/TCP
   - LoadBalancer IP from MetalLB
   - ConfigMap for tacacs.conf

3. **Network Switches** (Cisco IOS)
   - AAA configured to use TACACS+ server
   - Fallback to local admin account

### Network Flow

```
User SSH → Switch
            ↓
        TACACS+ query (shared secret)
            ↓
        TACACS+ Pod (LoadBalancer)
            ↓
        LDAP query (bind DN)
            ↓
        Authentik LDAP Outpost
            ↓
        Authentik Server
```

## User & Group Management

### Group to Privilege Mapping

| Authentik Group | Privilege | Access Level |
|----------------|-----------|--------------|
| network-admins | 15 | Full config, enable mode, reload |
| network-operators | 7 | Read-only, show, ping, traceroute |
| network-readonly | 1 | Basic show commands only |

### User Lifecycle

1. **Add User**: Create in Authentik → Add to group → Immediate switch access
2. **Change Role**: Move between groups → Privilege updates on next login
3. **Remove User**: Delete from Authentik → Access revoked immediately
4. **Emergency Access**: Local admin account always available

## Switch Configuration

```ios
! Enable AAA
aaa new-model

! TACACS+ server
tacacs-server host <tacacs-ip>
tacacs-server key <shared-secret>

! Authentication: TACACS+ first, local fallback
aaa authentication login default group tacacs+ local

! Authorization: TACACS+ determines privilege level
aaa authorization exec default group tacacs+ local

! Accounting: Log all commands
aaa accounting exec default start-stop group tacacs+
aaa accounting commands 15 default start-stop group tacacs+
```

## Monitoring

### Metrics (Prometheus)
- auth_attempts_total
- auth_failures_total
- active_sessions

### Alerts
- `TACACSServerDown` - No pods running (critical)
- `TACACSHighFailureRate` - >10 failures in 5 min (warning)

## Security Considerations

- **Shared Secret**: Strong random key (32+ chars), stored in Vault
- **LDAP Bind Account**: Read-only service account
- **Local Fallback**: Admin account preserved for emergency
- **Encryption**: TACACS+ encrypts entire packet
- **Audit Logging**: All commands logged to accounting file
