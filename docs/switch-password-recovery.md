# Switch Password Recovery Procedure

## Symptom

SSH authentication fails for `ansible` and `localadmin` users despite credentials matching Vault:

```
10.0.99.101 raised Net::SSH::AuthenticationFailed
Permission denied (publickey,keyboard-interactive,password)
```

## Diagnosis

**Working:**
- Switch is reachable (ping: ✓)
- SSH port 22 open (✓)
- VLAN 99 configured (10.0.99.101/24)
- Hostname set (mgmt-sw-01)

**Failing:**
- SSH authentication with vault credentials
- Both `ansible` and `localadmin` users

**Expected Configuration:**
```
username ansible privilege 15 secret 747IFpeMAO/T2JLE0RaLZxzOF0dO9qxK
username localadmin privilege 15 secret 747IFpeMAO/T2JLE0RaLZxzOF0dO9qxK
enable secret F2zRdxL/WrifPb0f8siRdDQUUp4BzzJ1
```

## Possible Causes

1. **ZTP Bootstrap Not Applied**
   - Config file exists in TFTP: `/srv/tftp/network-confg`
   - May not have been downloaded/applied by switch

2. **Provision Playbook Never Run**
   - Bootstrap only creates minimal config
   - Full config requires `ansible-playbook provision-new-switch.yml`

3. **Password Format Issue**
   - `secret` command may have hashed differently than expected
   - Special characters in password may need escaping

4. **Configuration Overwrite**
   - Switch may have been manually reconfigured
   - Another automation tool may have changed credentials

## Recovery Options

### Option 1: Console Access (Recommended)

1. Connect to switch console port (physical access required)
2. Verify current configuration:
   ```
   show run | inc username
   show run | inc enable
   ```

3. Reset password if needed:
   ```
   conf t
   username ansible privilege 15 secret 747IFpeMAO/T2JLE0RaLZxzOF0dO9qxK
   username localadmin privilege 15 secret 747IFpeMAO/T2JLE0RaLZxzOF0dO9qxK
   enable secret F2zRdxL/WrifPb0f8siRdDQUUp4BzzJ1
   end
   write memory
   ```

### Option 2: Password Recovery Mode

1. Interrupt boot process (hold Mode button during power-on for 2960X)
2. Boot into ROMMON
3. Reset password using standard Cisco recovery procedure
4. Reapply ZTP bootstrap or provision playbook

### Option 3: Factory Reset + Re-provision

1. Factory reset the switch
2. Power cycle with DHCP option 150 pointing to ZTP server
3. Verify ZTP bootstrap applied
4. Run provision playbook:
   ```bash
   cd ansible
   export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
   ansible-playbook playbooks/provision-new-switch.yml \
     -e target_switch=mgmt-sw-01 \
     -e switch_ansible_password=<from_vault> \
     -e switch_enable_secret=<from_vault>
   ```

## Test Credentials

After recovery, test authentication:

```bash
# Test SSH authentication
sshpass -p '<password>' ssh ansible@10.0.99.101 'show version'

# Test with test script
./ansible/scripts/test-switch-credentials.sh mgmt-sw-01
```

## Vault Credentials

Retrieve current credentials from Vault:

```bash
vault kv get -field=ansible_password secret/infrastructure/switches/global
vault kv get -field=enable_secret secret/infrastructure/switches/global
```

## Prevention

1. **Verify ZTP Bootstrap**
   - Check TFTP logs for download confirmation
   - Console into switch after ZTP to verify config

2. **Run Provision Playbook**
   - Always run provision playbook after ZTP
   - Verify SSH access before considering switch "provisioned"

3. **Document Console Access**
   - Keep console cable accessible
   - Document physical location and access procedure

4. **Monitor Switch Health**
   - Oxidized will alert on failed backups
   - SNMP monitoring can detect configuration drift

## Related Files

- ZTP Bootstrap Template: `ansible/templates/switches/ztp-bootstrap.j2`
- Provision Playbook: `ansible/playbooks/provision-new-switch.yml`
- Full Config Template: `ansible/templates/switches/edge-ios.j2`
- Vault Secrets: `secret/infrastructure/switches/global`
