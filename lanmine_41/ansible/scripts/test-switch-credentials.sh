#!/bin/bash
# Test SSH credentials for Cisco switches
# Usage: ./test-switch-credentials.sh <switch-ip-or-hostname>

set -euo pipefail

SWITCH="${1:-}"
if [ -z "$SWITCH" ]; then
  echo "Usage: $0 <switch-ip-or-hostname>"
  echo "Example: $0 mgmt-sw-01"
  echo "Example: $0 10.0.99.101"
  exit 1
fi

# Get credentials from Vault
export VAULT_ADDR="${VAULT_ADDR:-https://vault-01.lionfish-caiman.ts.net:8200}"
ANSIBLE_USER=$(vault kv get -field=ansible_user secret/infrastructure/switches/global 2>/dev/null || echo "")
ANSIBLE_PASSWORD=$(vault kv get -field=ansible_password secret/infrastructure/switches/global 2>/dev/null || echo "")
ENABLE_SECRET=$(vault kv get -field=enable_secret secret/infrastructure/switches/global 2>/dev/null || echo "")

if [ -z "$ANSIBLE_PASSWORD" ]; then
  echo "❌ Failed to retrieve credentials from Vault"
  echo "   Make sure VAULT_TOKEN is set and vault is accessible"
  exit 1
fi

echo "Testing SSH connectivity to $SWITCH..."
echo

# Test 1: Basic connectivity
echo "Test 1: Network connectivity"
if ping -c 2 -W 2 "$SWITCH" >/dev/null 2>&1; then
  echo "✓ Ping successful"
else
  echo "✗ Ping failed - switch may be unreachable"
  exit 1
fi

# Test 2: SSH port
echo
echo "Test 2: SSH port (22/tcp)"
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${SWITCH}/22" 2>/dev/null; then
  echo "✓ SSH port open"
else
  echo "✗ SSH port closed or filtered"
  exit 1
fi

# Test 3: SSH authentication methods
echo
echo "Test 3: Available authentication methods"
METHODS=$(nmap -p 22 --script ssh-auth-methods --script-args="ssh.user=${ANSIBLE_USER}" "$SWITCH" 2>&1 | grep -A 5 "auth-methods" || echo "Unknown")
echo "$METHODS"

# Test 4: SSH authentication with ansible user
echo
echo "Test 4: SSH authentication (user: ${ANSIBLE_USER})"
if sshpass -p "${ANSIBLE_PASSWORD}" ssh -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 \
  -o PreferredAuthentications=password \
  "${ANSIBLE_USER}@${SWITCH}" 'show version | include IOS|uptime' 2>/dev/null | head -5; then
  echo "✓ SSH authentication successful"
  echo
  echo "✓ All tests passed - switch is accessible"
  exit 0
else
  echo "✗ SSH authentication failed"
  echo
  echo "Debugging information:"
  echo "  Username: ${ANSIBLE_USER}"
  echo "  Password: ${ANSIBLE_PASSWORD:0:10}... (${#ANSIBLE_PASSWORD} chars)"
  echo "  Enable secret: ${ENABLE_SECRET:0:10}... (${#ENABLE_SECRET} chars)"
  echo
  echo "Possible causes:"
  echo "  1. Switch doesn't have user '${ANSIBLE_USER}' configured"
  echo "  2. Password in Vault doesn't match switch configuration"
  echo "  3. ZTP bootstrap was not applied"
  echo "  4. Provision playbook was not run"
  echo
  echo "See docs/switch-password-recovery.md for recovery procedures"
  exit 1
fi
