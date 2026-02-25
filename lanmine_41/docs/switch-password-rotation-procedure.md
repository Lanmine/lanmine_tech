# Switch Password Rotation Procedure

**CRITICAL:** This procedure changes authentication credentials. Follow carefully to avoid lockout.

## Prerequisites

- Console access to switch (for emergency recovery)
- Current credentials working in Vault
- Backup of current configuration

## Generated Credentials

```bash
NEW_PASSWORD="wR0x1ei3UX7nZ/poZyBe1gExKxEkjBcyxviiqwt2+5U="
NEW_ENABLE="b4yE0ecSpbz4ErI3sYAcmOV3P8kPYjP9id5YMDp3iZE="
```

## Step 1: Configure Switch

```yaml
---
- name: Rotate switch passwords
  hosts: mgmt-sw-01
  gather_facts: no
  vars:
    new_password: "wR0x1ei3UX7nZ/poZyBe1gExKxEkjBcyxviiqwt2+5U="
    new_enable: "b4yE0ecSpbz4ErI3sYAcmOV3P8kPYjP9id5YMDp3iZE="
  tasks:
    - name: Update admin password
      cisco.ios.ios_config:
        lines:
          - "username admin privilege 15 secret {{ new_password }}"
        save_when: modified

    - name: Update enable secret
      cisco.ios.ios_config:
        lines:
          - "enable secret {{ new_enable }}"
        save_when: modified
```

## Step 2: Update Vault

```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"

vault kv put secret/infrastructure/switches/global \
  ansible_user=admin \
  ansible_password="wR0x1ei3UX7nZ/poZyBe1gExKxEkjBcyxviiqwt2+5U=" \
  enable_secret="b4yE0ecSpbz4ErI3sYAcmOV3P8kPYjP9id5YMDp3iZE=" \
  snmp_v3_auth_pass=ylr4EqrQrCKfiIhUUHZm2MG1Mceklc6C \
  snmp_v3_priv_pass=zUEwn0QkTkouBwIi6bkMM52CiyGPAkKp
```

## Step 3: Update Oxidized Secrets

```bash
kubectl patch secret oxidized-secrets -n oxidized --type=json -p='[
  {"op": "replace", "path": "/data/ios_password", "value": "'$(echo -n "wR0x1ei3UX7nZ/poZyBe1gExKxEkjBcyxviiqwt2+5U=" | base64 -w0)'"},
  {"op": "replace", "path": "/data/ios_enable_password", "value": "'$(echo -n "b4yE0ecSpbz4ErI3sYAcmOV3P8kPYjP9id5YMDp3iZE=" | base64 -w0)'"}
]'

# Restart Oxidized to pick up new credentials
kubectl rollout restart deployment/oxidized -n oxidized
```

## Step 4: Verify

### Test Ansible
```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
export NETBOX_TOKEN=$(vault kv get -field=api_token secret/infrastructure/netbox)

ansible -i inventory/ mgmt-sw-01 -m cisco.ios.ios_command -a "commands='show version'"
```

### Test Oxidized
```bash
kubectl logs -n oxidized deployment/oxidized -c oxidized --tail=20
# Should show successful backup of mgmt-sw-01
```

### Test Direct SSH
```bash
./scripts/test-switch-credentials.sh 10.0.99.101
# Should show "✓ All tests passed"
```

## Rollback Procedure

If new credentials don't work:

### Console Access Required
1. Connect via console cable
2. Enter ROMMON mode (power cycle + Break key)
3. Follow password recovery procedure in `docs/switch-password-recovery.md`
4. Restore old password from Vault history:
   ```bash
   vault kv get -version=6 secret/infrastructure/switches/global
   ```

## Security Notes

- Old password: `ch4nge-th1s-passw0rd-s00n` (default, INSECURE)
- New password: 32-byte base64 random (256 bits entropy)
- Rotation frequency: Every 90 days recommended
- Store rotation date in Vault metadata:
  ```bash
  vault kv metadata put secret/infrastructure/switches/global \
    custom_metadata=last_rotation="2026-01-23"
  ```
