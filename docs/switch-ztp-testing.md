# Switch ZTP Testing and Validation Guide

This guide provides comprehensive testing procedures to validate the entire ZTP system before deploying to production Nexus core switches.

## Table of Contents

1. [Pre-Deployment Tests](#pre-deployment-tests)
2. [ZTP Workflow Test](#ztp-workflow-test)
3. [Production Validation](#production-validation)
4. [Monitoring Validation](#monitoring-validation)
5. [Troubleshooting](#troubleshooting)
6. [Success Criteria](#success-criteria)

## Pre-Deployment Tests

Run these tests before attempting ZTP on any switch.

### 1. Vault Secrets Verification

```bash
# Test Vault connectivity
vault status

# Verify SNMP credentials exist
vault kv get secret/infrastructure/snmp

# Verify switch credentials exist
vault kv get secret/infrastructure/switches

# Verify bootstrap template is stored
vault kv get secret/infrastructure/switch-configs

# Expected output: All secrets readable with correct keys
```

### 2. ZTP Server Services

```bash
# Check TFTP server status
sudo systemctl status tftpd-hpa
sudo ss -ulnp | grep :69

# Check nginx status
sudo systemctl status nginx
sudo ss -tlnp | grep :8080

# Verify TFTP file serving
tftp -v 10.0.10.21 -c get poap_nexus.py /tmp/test_poap.py
ls -lh /tmp/test_poap.py

# Verify nginx file serving
curl -I http://10.0.10.21:8080/poap_nexus.py
curl -I http://10.0.10.21:8080/bootstrap-config.cfg
```

### 3. TFTP Download Test

```bash
# Test POAP script download
cd /tmp
tftp -v 10.0.10.21 -c get poap_nexus.py test_poap.py
md5sum test_poap.py /srv/tftp/poap_nexus.py  # Should match

# Test bootstrap config download
curl -o test_bootstrap.cfg http://10.0.10.21:8080/bootstrap-config.cfg
md5sum test_bootstrap.cfg /var/www/switch-ztp/bootstrap-config.cfg  # Should match
```

### 4. Ansible Inventory Test

```bash
cd ansible

# Test inventory parsing
ansible-inventory --list | jq '.switches.hosts'

# Test Vault integration
ansible all -i inventory/switches.yml -m ping --limit core-sw-01

# Verify host variables
ansible-inventory --host core-sw-01 | jq '.'

# Expected output: Variables from Vault should be present
```

### 5. Template Rendering Test

```bash
cd ansible

# Test bootstrap template with dummy switch
ansible-playbook playbooks/generate-bootstrap-config.yml \
  --extra-vars "target_switch=core-sw-01" \
  --check

# Verify rendered config
cat /var/www/switch-ztp/bootstrap-config.cfg

# Check for:
# - Correct hostname
# - Management IP
# - SNMP community
# - Credentials from Vault
```

## ZTP Workflow Test

Test the complete ZTP workflow using a spare switch or lab switch.

### Prerequisites

- Spare Nexus switch in factory default state
- Switch connected to management network (VLAN 10)
- DHCP option 150 configured to point to 10.0.10.21
- Ansible inventory includes test switch

### Step 1: Prepare Test Switch

```bash
# Factory reset test switch (if not already)
# On switch console:
write erase
reload

# Confirm: This will reset the entire configuration. Continue? (yes/no) [n] yes
```

### Step 2: Generate Bootstrap Config

```bash
cd ansible

# Generate config for test switch
ansible-playbook playbooks/generate-bootstrap-config.yml \
  --extra-vars "target_switch=test-sw-01"

# Verify config
cat /var/www/switch-ztp/bootstrap-config.cfg
```

### Step 3: Monitor ZTP Process

```bash
# On switch console, watch POAP progress
# Expected timeline:
# T+0:00 - DHCP request (should get IP from 10.0.10.100-110 pool)
# T+0:30 - TFTP download of poap_nexus.py from 10.0.10.21
# T+1:00 - HTTP download of bootstrap-config.cfg from 10.0.10.21:8080
# T+2:00 - Config application and reload
# T+5:00 - Switch online with bootstrap config

# Monitor from ZTP server
sudo tail -f /var/log/syslog | grep -i 'tftp\|dhcp'
sudo tail -f /var/log/nginx/access.log
```

### Step 4: Validate Bootstrap Config

```bash
# SSH to test switch (using credentials from Vault)
ssh admin@10.0.10.30

# Verify hostname
show running-config | include hostname

# Verify management interface
show running-config interface mgmt0

# Verify SNMP
show running-config | section snmp

# Verify user accounts
show running-config | section username
```

### Step 5: Apply Full Configuration

```bash
cd ansible

# Run full configuration playbook
ansible-playbook playbooks/configure-switches.yml --limit test-sw-01

# Validate configuration
ansible-playbook playbooks/validate-switch-config.yml --limit test-sw-01
```

### Expected Test Results

| Check | Expected Result |
|-------|----------------|
| DHCP IP assignment | 10.0.10.100-110 range |
| POAP script download | Success within 60s |
| Bootstrap config download | Success within 90s |
| SSH access | Success within 5 minutes |
| Hostname | Matches inventory |
| Management IP | 10.0.10.30/24 |
| SNMP response | snmpwalk succeeds |
| Full config application | All tasks succeed |

## Production Validation

Pre-deployment checks for production Nexus core switches.

### 1. vPC Status Verification

```bash
# On core-sw-01
show vpc brief
show vpc consistency-parameters global
show vpc consistency-parameters interface port-channel10

# On core-sw-02
show vpc brief
show vpc consistency-parameters global
show vpc consistency-parameters interface port-channel10

# Expected: vPC domain up, peer-link up, all port-channels up
```

### 2. VLAN Validation

```bash
# Verify all VLANs exist
show vlan brief | include "10\|20\|30"

# Verify VLAN trunking on uplinks
show interface trunk

# Expected: VLANs 1,10,20,30 active and allowed on trunks
```

### 3. Interface Status

```bash
# Verify uplink status
show interface Ethernet1/1-2 status
show interface port-channel10 status

# Verify LANcache LAG
show interface Ethernet1/49-50 status
show interface port-channel1 status

# Expected: All interfaces up, port-channels up
```

### 4. Environment and Logs

```bash
# Check system health
show environment
show module

# Review logs for errors
show logging last 100 | include ERROR

# Expected: No critical errors, all modules online
```

### 5. Backup Current Configuration

```bash
# Before making ANY changes to production
cd ansible
ansible-playbook playbooks/backup-switches.yml --limit core_switches

# Verify backups
ls -lh backups/
git status
```

## Monitoring Validation

Verify monitoring stack integration after ZTP.

### 1. SNMP Exporter Test

```bash
# Test SNMP exporter scraping switch
curl -s "http://10.0.10.26:9116/snmp?target=10.0.10.30&module=cisco_nexus" | grep -v '^#'

# Expected: Metrics for interfaces, CPU, memory, temperature
```

### 2. Prometheus Targets

```bash
# Check Prometheus targets (via Grafana or Prometheus UI)
curl -s http://prometheus.lionfish-caiman.ts.net/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "snmp-switches")'

# Expected: core-sw-01 and core-sw-02 targets with state="up"
```

### 3. Grafana Dashboard

```bash
# Access Grafana
open https://grafana.lionfish-caiman.ts.net

# Navigate to "Network Switches - Overview" dashboard
# Verify:
# - Both switches showing data
# - Interface counters incrementing
# - No alerts firing
```

### 4. Hubble Flow Visibility

```bash
# Access Hubble UI
open https://hubble.lionfish-caiman.ts.net

# Verify:
# - Flows visible from switch management IPs
# - SNMP traffic to switches visible
```

## Troubleshooting

Common issues and resolutions.

### TFTP Download Fails

**Symptoms:**
```
POAP: Failed to download POAP script from TFTP server
```

**Diagnosis:**
```bash
# Check TFTP service
sudo systemctl status tftpd-hpa
sudo ss -ulnp | grep :69

# Test TFTP from another host
tftp -v 10.0.10.21 -c get poap_nexus.py /tmp/test.py

# Check file permissions
ls -lh /srv/tftp/poap_nexus.py
```

**Resolution:**
```bash
# Restart TFTP service
sudo systemctl restart tftpd-hpa

# Fix permissions
sudo chmod 644 /srv/tftp/poap_nexus.py
sudo chown tftp:tftp /srv/tftp/poap_nexus.py
```

### DHCP Option 150 Not Applied

**Symptoms:**
```
Switch gets DHCP IP but doesn't attempt TFTP download
```

**Diagnosis:**
```bash
# On OPNsense, check Kea DHCP config
cat /usr/local/etc/kea/kea-dhcp4.conf | grep -A5 'option-data.*150'

# Check DHCP logs
tail -f /var/log/dhcpd.log
```

**Resolution:**
```bash
# Verify DHCP option 150 in Kea config
# Should have: "name": "tftp-server-address", "data": "10.0.10.21"

# Restart Kea
service kea-dhcp4 restart
```

### Bootstrap Config Not Loading

**Symptoms:**
```
POAP script downloads but config not applied
```

**Diagnosis:**
```bash
# Check nginx access logs
sudo tail -f /var/log/nginx/access.log

# Test HTTP download
curl -v http://10.0.10.21:8080/bootstrap-config.cfg

# Verify config syntax
nxos-validator bootstrap-config.cfg  # If tool available
```

**Resolution:**
```bash
# Regenerate config
cd ansible
ansible-playbook playbooks/generate-bootstrap-config.yml --extra-vars "target_switch=core-sw-01"

# Restart nginx
sudo systemctl restart nginx
```

### Ansible Connection Fails

**Symptoms:**
```
fatal: [core-sw-01]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host"}
```

**Diagnosis:**
```bash
# Test SSH manually
ssh -vvv admin@10.0.10.30

# Verify credentials in Vault
vault kv get secret/infrastructure/switches

# Check inventory
ansible-inventory --host core-sw-01
```

**Resolution:**
```bash
# Ensure SSH keys are accepted
ssh-keyscan 10.0.10.30 >> ~/.ssh/known_hosts

# Test with password auth
ansible core-sw-01 -m ping -k

# Verify Vault token
vault token lookup
```

### vPC Peer-Link Down After Config

**Symptoms:**
```
vPC peer-link down after applying configuration
```

**Diagnosis:**
```bash
# Check vPC status
show vpc brief
show vpc consistency-parameters global

# Check peer-link interfaces
show interface Ethernet1/1-2 status
show port-channel 10
```

**Resolution:**
```bash
# Verify peer-link config on BOTH switches
show running-config interface port-channel10

# Ensure vPC domain IDs match
show running-config | section "vpc domain"

# Reload peer-link
configure terminal
interface port-channel10
shutdown
no shutdown
```

## Success Criteria

Mark each item complete before deploying to production.

### Pre-Deployment Checklist

- [ ] All Vault secrets readable (SNMP, credentials, bootstrap template)
- [ ] TFTP server responding on port 69
- [ ] nginx serving files on port 8080
- [ ] TFTP download test successful from remote host
- [ ] Ansible inventory parses without errors
- [ ] Vault integration working in Ansible
- [ ] Bootstrap template renders correctly for test switch
- [ ] DHCP option 150 configured in Kea (10.0.10.21)

### ZTP Workflow Checklist

- [ ] Test switch receives DHCP IP in 10.0.10.100-110 range
- [ ] POAP script downloads via TFTP within 60 seconds
- [ ] Bootstrap config downloads via HTTP within 90 seconds
- [ ] Switch applies bootstrap config and reloads
- [ ] SSH access works within 5 minutes of reload
- [ ] Hostname matches inventory
- [ ] Management IP correctly assigned (10.0.10.30/24)
- [ ] SNMP community configured and responding
- [ ] Full Ansible playbook runs without errors

### Production Validation Checklist

- [ ] Current configurations backed up to git
- [ ] vPC peer-link up and stable
- [ ] vPC domain consistency verified
- [ ] All VLANs active (1, 10, 20, 30)
- [ ] Uplink port-channels up
- [ ] LANcache LAG (Eth1/49-50, Po1) up
- [ ] No critical errors in logs
- [ ] Environment sensors normal

### Monitoring Checklist

- [ ] SNMP exporter scraping switches successfully
- [ ] Prometheus showing both switches as "up" targets
- [ ] Grafana dashboard displaying switch metrics
- [ ] Interface counters incrementing
- [ ] No monitoring alerts firing
- [ ] Hubble showing switch management traffic

### Documentation Checklist

- [ ] ZTP workflow documented in this guide
- [ ] Troubleshooting steps validated
- [ ] Production runbook created
- [ ] Team trained on ZTP process
- [ ] Rollback procedure documented

## Next Steps

After all success criteria are met:

1. **Schedule Production Deployment:**
   - Choose maintenance window
   - Notify stakeholders
   - Prepare rollback plan

2. **Deploy to First Core Switch:**
   - Start with core-sw-01
   - Monitor vPC status
   - Validate traffic flow

3. **Deploy to Second Core Switch:**
   - Apply to core-sw-02
   - Verify vPC convergence
   - Validate full redundancy

4. **Post-Deployment Monitoring:**
   - Watch for 24 hours
   - Review metrics in Grafana
   - Check for anomalies

See `docs/switch-ztp-production-runbook.md` for detailed deployment procedures.
