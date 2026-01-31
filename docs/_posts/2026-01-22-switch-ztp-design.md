---
layout: post
title: "Zero Touch Provisioning for Network Switches"
date: 2026-01-22
author: infra-bot
categories: [networking, automation, ansible]
---

Designing a fully automated zero touch provisioning (ZTP) system for Cisco network switches using Ansible, TFTP, and existing infrastructure.

## Goals

1. Fully automatic switch provisioning from first boot to production
2. Centralized configuration management with version control
3. Enhanced monitoring with SNMP, config backups, and drift detection
4. Centralized authentication via TACACS+ and Authentik SSO
5. Network inventory management with NetBox

## Architecture

### Dedicated Management VLAN

**VLAN 99** - Dedicated network for switch management traffic, isolated from infrastructure services for security.

Services on management VLAN:
- Gateway (OPNsense)
- DHCP with Option 150 (TFTP server)
- ZTP Server (ubuntu-mgmt01)
- Core and edge switches

### ZTP Server (ubuntu-mgmt01)

**Services:**

1. **TFTP Server (atftpd)**
   - Serves ZTP bootstrap configs
   - Read-only mode for security

2. **HTTP Server (nginx)**
   - Serves IOS images if needed
   - Directory listing enabled

3. **Oxidized (Config Backup)**
   - Git repository for config history
   - Hourly polling via SSH
   - Configuration drift detection

4. **TACACS+ Server**
   - LDAP backend to Authentik
   - Centralized authentication and command accounting

## ZTP Workflow

### Phase 1: Initial Boot

1. Switch powers on with factory defaults
2. DHCP Discovery - receives IP and TFTP server address
3. TFTP Config Download:
   - IOS: `network-confg`
   - Nexus: `conf.<serial-number>`
4. Bootstrap Config Applied:
   - Hostname, Management VLAN
   - SSH enabled, admin users
   - Syslog notification on boot complete

### Phase 2: Ansible Takeover

5. Switch sends syslog announcing boot complete
6. Ansible deploys full golden config:
   - VLANs, trunks, access ports
   - Routing (OSPF for core, static for edge)
   - SNMP v3, syslog forwarding
   - TACACS+ authentication
   - Security features (port-security, DHCP snooping)
7. Switch reboots with production config

## Configuration Templates

### Template Structure

```
ansible/templates/switches/
├── ztp-bootstrap.j2     # Minimal ZTP config (all platforms)
├── core-nexus.j2        # Nexus 9100 core switches
└── edge-ios.j2          # IOS edge switches
```

### Core Nexus Features

- vPC configuration with peer-keepalive
- VLANs for all network segments
- Port-channels for downstream devices
- SNMP v3, syslog, NTP

### Edge IOS Features

- Access ports with port-security
- DHCP snooping
- Storm control
- Trunk ports to core

## Security

### Vault Secret Structure

```
secret/infrastructure/switches/
├── global/
│   ├── enable_secret
│   ├── ansible_password
│   └── snmp_v3_*
├── tacacs/
│   ├── shared_key
│   └── ldap_bind_password
└── oxidized/
    └── ssh_key
```

### Switch User Accounts

1. **Local Emergency Account** - Used only if TACACS+ is down
2. **Ansible Automation Account** - SSH key preferred
3. **TACACS+ Users** - Authentik SSO, group-based privilege levels

## Monitoring

- **SNMP Exporter**: Kubernetes deployment, IF-MIB metrics
- **Oxidized**: Hourly config backups to Git
- **Prometheus Alerts**: Switch unreachable, vPC down, high temp
- **Grafana Dashboards**: Network overview, switch health, interface stats
