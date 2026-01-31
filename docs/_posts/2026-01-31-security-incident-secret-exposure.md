---
layout: post
title: "Security Incident: Committed Secrets and Remediation"
date: 2026-01-31
categories: [security, incident-response]
tags: [secrets, git, vault, kubernetes]
---

## Summary

On January 31, 2026, we discovered that 37 plaintext secrets had been committed to our infrastructure repository over time. These included database credentials, API tokens, RADIUS shared secrets, and Vault AppRole credentials. This post documents the incident, root cause analysis, and remediation steps taken.

## Timeline

- **Discovery**: Infrastructure analysis revealed plaintext secrets in Kubernetes manifests and Ansible configuration
- **Root Cause Analysis**: Investigated why pre-commit secret scanning failed to detect the commits
- **Remediation**: Rotated all exposed credentials, migrated to ExternalSecret pattern, scrubbed Git history
- **Prevention**: Enhanced secret scanning with dual-tool approach

## Affected Credentials

| Service | Credential Type | Location |
|---------|-----------------|----------|
| NetBox | PostgreSQL password | `kubernetes/apps/netbox/secrets.yaml` |
| NetBox | Django SECRET_KEY | `kubernetes/apps/netbox/secrets.yaml` |
| NetBox | Superuser password | `kubernetes/apps/netbox/secrets.yaml` |
| NetBox | API token | `kubernetes/apps/netbox/secrets.yaml` |
| NetBox | OAuth client secret | `kubernetes/apps/netbox/secrets.yaml` |
| cert-manager | Vault AppRole credentials | `kubernetes/infrastructure/cert-manager/vault-approle-secret.yaml` |
| PAM RADIUS | Shared secret | `ansible/roles/pam_radius/defaults/main.yml` |

## Root Cause Analysis

### Why TruffleHog Didn't Catch the Secrets

Our pre-commit configuration used TruffleHog with the `--only-verified` flag:

```yaml
# Previous configuration (vulnerable)
- repo: https://github.com/trufflesecurity/trufflehog
  hooks:
    - id: trufflehog
      entry: trufflehog git file://. --since-commit HEAD --only-verified --fail
```

The `--only-verified` flag instructs TruffleHog to only report secrets it can verify against live services. This is problematic for:

1. **Internal services** - PostgreSQL passwords, RADIUS secrets, and internal API tokens cannot be verified externally
2. **Generic patterns** - High-entropy strings that look like passwords but don't match known API formats
3. **Base64-encoded secrets** - Kubernetes secrets with base64-encoded values

This effectively silenced all alerts for our internal infrastructure credentials.

## Remediation Steps

### 1. Credential Rotation

All exposed credentials were rotated:

```bash
# NetBox credentials rotated in Vault
vault kv put secret/infrastructure/netbox \
  db_host="postgres-01.lionfish-caiman.ts.net" \
  db_port="5432" \
  db_name="netbox" \
  db_user="netbox" \
  db_password="<new-random-password>" \
  secret_key="<new-50-char-random-key>" \
  superuser_password="<new-password>" \
  superuser_api_token="<new-token>" \
  oauth_client_id="<existing-id>" \
  oauth_client_secret="<new-secret>" \
  redis_host="netbox-redis" \
  redis_port="6379"

# RADIUS shared secret rotated
vault kv put secret/authentik/radius \
  shared_secret="<new-32-char-hex>"

# Vault AppRole recreated
vault write -f auth/approle/role/cert-manager/secret-id
```

### 2. Migration to ExternalSecret Pattern

Replaced hardcoded Kubernetes secrets with ExternalSecret resources that pull from Vault:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: netbox-postgres
  namespace: netbox
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: netbox-postgres
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: infrastructure/netbox
        property: db_password
```

### 3. Git History Scrubbing

Removed sensitive files from all 415 commits using git-filter-repo:

```bash
git filter-repo --invert-paths --paths-from-file paths-to-remove.txt --force
```

Files removed:
- `kubernetes/apps/netbox/secrets.yaml`
- `kubernetes/infrastructure/cert-manager/vault-approle-secret.yaml`

### 4. Enhanced Secret Scanning

Updated pre-commit configuration with dual-tool approach:

```yaml
repos:
  # TruffleHog - removed --only-verified flag
  - repo: https://github.com/trufflesecurity/trufflehog
    rev: v3.88.0
    hooks:
      - id: trufflehog
        name: TruffleHog Secret Scan
        entry: trufflehog git file://. --since-commit HEAD --fail --no-update
        language: system
        pass_filenames: false

  # Gitleaks - entropy-based detection
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
        name: Gitleaks Secret Scan
        entry: gitleaks protect --staged --verbose
        language: system
        pass_filenames: false
```

Created custom Gitleaks configuration (`.gitleaks.toml`) with rules for:
- Kubernetes Secret stringData blocks
- RADIUS shared secrets
- Vault AppRole credentials
- Django SECRET_KEY
- High-entropy password fields (threshold: 3.5)

### 5. Updated .gitignore

Added patterns to prevent accidental commits:

```gitignore
# Kubernetes secrets with plaintext credentials
kubernetes/apps/netbox/secrets.yaml
kubernetes/infrastructure/cert-manager/vault-approle-secret.yaml
```

### 6. CI/CD Pipeline Updates

Updated GitHub Actions workflow to use both scanners without the `--only-verified` flag.

## Lessons Learned

1. **Verify what "verified" means** - The `--only-verified` flag sounds secure but actually reduces detection coverage for internal credentials

2. **Use multiple scanning tools** - Different tools have different detection strengths:
   - TruffleHog: Excellent for known API key formats
   - Gitleaks: Better for entropy-based and custom pattern detection

3. **Test your security controls** - Periodically audit whether your pre-commit hooks would catch test secrets

4. **Prefer external secret management** - Use ExternalSecret Operator to pull secrets from Vault rather than committing them

5. **Defense in depth** - Multiple layers of protection:
   - Pre-commit hooks (local development)
   - CI/CD scanning (PR validation)
   - .gitignore patterns (accidental prevention)
   - Code review (human verification)

## Verification

After remediation, verified all ExternalSecrets are syncing successfully:

```bash
$ kubectl get externalsecrets -n netbox
NAME              STORE   REFRESH   STATUS
netbox-oauth      vault   1h        SecretSynced
netbox-postgres   vault   1h        SecretSynced
netbox-redis      vault   1h        SecretSynced
netbox-secret     vault   1h        SecretSynced
netbox-superuser  vault   1h        SecretSynced
```

## Recommendations for Other Teams

1. **Audit your TruffleHog flags** - Remove `--only-verified` unless you specifically only care about verifiable external API keys

2. **Add Gitleaks as a second scanner** - The entropy-based detection catches what pattern matching misses

3. **Use ExternalSecret Operator** - Never commit Kubernetes secrets with actual values

4. **Regular secret audits** - Use tools like `gitleaks detect --source . --verbose` to scan your full repository history periodically

## References

- [TruffleHog Documentation](https://github.com/trufflesecurity/trufflehog)
- [Gitleaks Documentation](https://github.com/gitleaks/gitleaks)
- [External Secrets Operator](https://external-secrets.io/)
- [git-filter-repo](https://github.com/newren/git-filter-repo)
