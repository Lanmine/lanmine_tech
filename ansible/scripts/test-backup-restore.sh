#!/bin/bash
#
# Test backup restoration procedures
# Verifies that all encrypted backups can be decrypted using keys from Vault
#

set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-https://vault-01.lionfish-caiman.ts.net:8200}"

echo "════════════════════════════════════════════════════════════════"
echo "  Backup Restoration Test"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "════════════════════════════════════════════════════════════════"
echo

# Check Vault connectivity
if ! vault status >/dev/null 2>&1; then
  echo "❌ ERROR: Cannot connect to Vault at $VAULT_ADDR"
  echo "   Make sure you're authenticated: vault login"
  exit 1
fi

echo "✅ Vault connection OK"
echo

BACKUPS_DIR="$(cd "$(dirname "$0")/../backups" && pwd)"
FAILED=0
TESTED=0

for component in opnsense proxmox vault postgres; do
  echo "──────────────────────────────────────────────────────────────"
  echo "Testing: $component"
  echo "──────────────────────────────────────────────────────────────"

  # Get age private key from Vault
  SECRET_PATH="secret/infrastructure/${component}-backup"
  if ! AGE_KEY=$(vault kv get -field=age_private_key "$SECRET_PATH" 2>/dev/null); then
    echo "❌ FAILED: Cannot retrieve age key from $SECRET_PATH"
    ((FAILED++))
    echo
    continue
  fi

  echo "✅ Retrieved age private key from Vault"

  # Find latest backup
  LATEST=$(ls -t "$BACKUPS_DIR/$component"/*.age 2>/dev/null | head -1)
  if [ -z "$LATEST" ]; then
    echo "⚠️  WARNING: No backup files found in $BACKUPS_DIR/$component/"
    echo
    continue
  fi

  BACKUP_NAME=$(basename "$LATEST")
  BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST")) / 86400 ))

  echo "📦 Latest backup: $BACKUP_NAME"
  echo "📅 Backup age: $BACKUP_AGE days"

  # Test decryption
  echo "🔓 Testing decryption..."

  if OUTPUT=$(echo "$AGE_KEY" | age --decrypt -i - "$LATEST" 2>&1); then
    # Verify output is not empty
    if [ -z "$OUTPUT" ]; then
      echo "❌ FAILED: Decrypted content is empty"
      ((FAILED++))
    else
      LINES=$(echo "$OUTPUT" | wc -l)
      BYTES=$(echo "$OUTPUT" | wc -c)
      echo "✅ PASSED: Decryption successful"
      echo "   Output: $LINES lines, $BYTES bytes"

      # Verify file type
      case "$component" in
        opnsense)
          if echo "$OUTPUT" | head -1 | grep -q '<?xml'; then
            echo "   Format: Valid XML ✅"
          else
            echo "   ⚠️  Warning: Expected XML, got other format"
          fi
          ;;
        proxmox|vault)
          # Check for tar.gz magic bytes after decryption
          if echo "$OUTPUT" | head -c 2 | od -An -tx1 | grep -q "1f 8b"; then
            echo "   Format: Valid gzip ✅"
          else
            echo "   ⚠️  Warning: Expected gzip, got other format"
          fi
          ;;
        postgres)
          if echo "$OUTPUT" | head -5 | grep -q -E '^--|CREATE|INSERT|COPY'; then
            echo "   Format: Valid SQL ✅"
          else
            echo "   ⚠️  Warning: Expected SQL, got other format"
          fi
          ;;
      esac

      ((TESTED++))
    fi
  else
    echo "❌ FAILED: Decryption error"
    echo "   $OUTPUT"
    ((FAILED++))
  fi

  echo
done

echo "════════════════════════════════════════════════════════════════"
echo "  Test Summary"
echo "════════════════════════════════════════════════════════════════"
echo "  Tested:  $TESTED backups"
echo "  Failed:  $FAILED backups"
echo

if [ $FAILED -eq 0 ]; then
  echo "✅ All backup restoration tests passed!"
  echo
  echo "Next steps:"
  echo "  1. Print offline backup: cat ~/age-private-keys-OFFLINE-BACKUP.txt"
  echo "  2. Store printed copy in physical safe/vault"
  echo "  3. Test full restore in non-production environment"
  exit 0
else
  echo "❌ Some backup restoration tests failed!"
  echo "   Review errors above and fix issues before considering backups reliable"
  exit 1
fi
