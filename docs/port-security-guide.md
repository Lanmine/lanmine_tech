# Port Security Configuration Guide

## Overview

Port security on Cisco switches limits the number of MAC addresses that can be learned on a port, preventing MAC flooding attacks and unauthorized device connections.

## Configuration Summary

### Contestant Ports (VLAN 20)

**Interfaces:** Gi1/0/1-4, Gi1/0/22

**Settings:**
- Maximum MAC addresses: 3
- Violation action: `restrict` (drop packets, log, keep port up)
- MAC learning: Sticky (learned MACs saved to running-config)
- Aging: 24 hours of inactivity

**Use case:** LAN party contestants - allows gaming PC + phone + other device per port.

### Infrastructure Ports (VLAN 10)

**Interfaces:** Gi1/0/5-9 (when enabled)

**Settings:**
- Maximum MAC addresses: 1
- Violation action: `shutdown` (err-disable port on violation)
- MAC learning: Sticky
- Aging: 24 hours of inactivity

**Use case:** Critical infrastructure - one device per port, strict security.

## Violation Actions

| Action | Behavior | Use Case |
|--------|----------|----------|
| `protect` | Drop violating packets silently | No logging needed |
| `restrict` | Drop packets + log SNMP trap | Monitor violations, keep port up |
| `shutdown` | Err-disable port | Maximum security, requires manual recovery |

## Commands

### Apply Port Security

```bash
cd ansible
ansible-playbook playbooks/configure-port-security.yml
```

### Check Status

```bash
ansible-playbook playbooks/check-port-security-violations.yml
```

### Manual Verification

```bash
# On switch
show port-security
show port-security interface GigabitEthernet1/0/1
show port-security address
show interface status err-disabled
```

### Recover Err-Disabled Port

If a port is shut down due to violation:

1. **Investigate:** Check `show port-security address` for unauthorized MAC
2. **Remove offending device** from network
3. **Re-enable port:**
   ```bash
   ansible mgmt-sw-01 -i inventory/ -m cisco.ios.ios_config \
     -a "lines='shutdown,no shutdown' parents='interface GigabitEthernet1/0/X' save_when=modified"
   ```

Or manually:
```
configure terminal
interface GigabitEthernet1/0/X
shutdown
no shutdown
end
```

## Monitoring

Port security violations trigger:

1. **SNMP traps** → Prometheus Alertmanager
2. **Syslog messages** → Loki/Grafana
3. **Interface err-disable** → InterfaceDown alert

**Grafana dashboard:** Cisco Switch Dashboard → Port Security panel

## Sticky MAC Addresses

Sticky MAC learning automatically adds learned MACs to running-config:

```
interface GigabitEthernet1/0/1
 switchport port-security mac-address sticky 0011.2233.4455
```

**Save config** after devices connect to make sticky MACs persistent:
```bash
ansible mgmt-sw-01 -i inventory/ -m cisco.ios.ios_config -a "save_when=always"
```

## Aging

**Inactivity aging (24 hours):**
- MAC removed if no traffic for 24 hours
- Allows different devices during multi-day events
- Prevents stale MAC entries

**Absolute aging (alternative):**
```
switchport port-security aging type absolute
```
- MAC removed after fixed time regardless of activity

## Best Practices

1. **Test before production:** Apply to one port, verify behavior
2. **Use restrict for contestants:** Keeps port up, allows troubleshooting
3. **Use shutdown for infrastructure:** Maximum security for critical systems
4. **Monitor violations:** Set up alerts for security events
5. **Document exceptions:** Some ports may need higher MAC limits (e.g., uplinks)

## Troubleshooting

### Port shows err-disabled

**Cause:** Violation action set to `shutdown` and MAC limit exceeded

**Fix:** See "Recover Err-Disabled Port" above

### Legitimate device can't connect

**Cause:** Port already has maximum MACs learned

**Fix:**
1. Check learned MACs: `show port-security address interface GigabitEthernet1/0/X`
2. Clear old MACs: `clear port-security sticky interface GigabitEthernet1/0/X`
3. Or increase max MACs in playbook

### MAC address keeps changing

**Cause:** Some devices (virtualization hosts, routers) use multiple MACs

**Solution:**
- Increase `max_mac_addresses` for that port
- Or disable port security on uplink/trunk ports

## Security Considerations

**Port security does NOT protect against:**
- MAC spoofing (attacker using learned MAC)
- ARP poisoning
- VLAN hopping on trunk ports

**For comprehensive security, also implement:**
- DHCP snooping
- Dynamic ARP Inspection (DAI)
- IP Source Guard
- 802.1X authentication (see TACACS+ guide)

## References

- Cisco IOS Port Security Configuration Guide
- Ansible playbook: `playbooks/configure-port-security.yml`
- Monitoring playbook: `playbooks/check-port-security-violations.yml`
