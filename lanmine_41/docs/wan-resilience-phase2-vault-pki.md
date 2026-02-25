# WAN Resilience - Phase 2: Internal Certificate Authority

## Overview

Phase 2 establishes Vault PKI as an internal Certificate Authority for issuing TLS certificates to `*.lanmine.local` services. This ensures HTTPS works even during WAN outages, as certificates are issued by an internal CA rather than requiring external validation.

## Architecture

**Certificate Issuers (3 tiers):**
1. **vault-issuer** - Internal CA for `*.lanmine.local` (WAN-resilient)
2. **letsencrypt-prod** - Public CA for `*.hl0.dev` (WAN-dependent)
3. **lanmine-ca-issuer** - Self-signed fallback (existing)

**Vault PKI Setup:**
- **Path:** `pki/`
- **Root CA:** Lanmine Internal Root CA (10 year validity)
- **Role:** `lanmine-local` (allows `*.lanmine.local` certificates)
- **Max TTL:** 720h (30 days)

**cert-manager Integration:**
- **Authentication:** Vault AppRole
- **Policy:** `cert-manager` (allows signing/issuing from `pki/`)
- **Secret:** `vault-approle` in cert-manager namespace

## Implementation Status

✅ **Vault PKI Configured:**
```bash
vault secrets list | grep pki
# pki/     pki     pki_d8c5e5e5     n/a
```

✅ **Root CA Generated:**
```bash
vault read pki/cert/ca
# Issuer: CN=Lanmine Internal Root CA
# Validity: 10 years
```

✅ **PKI Role Created:**
```bash
vault read pki/roles/lanmine-local
# allowed_domains: [lanmine.local]
# allow_subdomains: true
# max_ttl: 720h
```

✅ **cert-manager AppRole:**
```bash
vault read auth/approle/role/cert-manager
# token_policies: [cert-manager]
```

✅ **Vault ClusterIssuer:**
```bash
kubectl get clusterissuer vault-issuer
# NAME           READY   AGE
# vault-issuer   True    5m
```

## Using Vault Certificates

### For New Services

Add to your Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: service-internal
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: vault-issuer
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - service.lanmine.local
    secretName: service-lanmine-tls
  rules:
  - host: service.lanmine.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: service
            port:
              number: 80
```

### For Existing Services

Update the `cert-manager.io/cluster-issuer` annotation:

```yaml
annotations:
  cert-manager.io/cluster-issuer: vault-issuer  # Changed from lanmine-ca-issuer
```

## Certificate Lifecycle

**Issuance:**
1. Create Ingress with `cert-manager.io/cluster-issuer: vault-issuer`
2. cert-manager authenticates to Vault via AppRole
3. cert-manager requests certificate from `pki/sign/lanmine-local`
4. Vault validates domain matches `*.lanmine.local`
5. Vault issues certificate signed by Root CA
6. cert-manager stores certificate in specified secretName

**Renewal:**
- Automatic renewal at 2/3 of certificate lifetime (~20 days for 30-day cert)
- No WAN connectivity required (internal Vault CA)

**Revocation:**
```bash
# Get certificate serial
kubectl get certificate <name> -n <namespace> -o yaml

# Revoke in Vault
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
vault write pki/revoke serial_number=<serial>
```

## DNS + Certificate Integration

**Dual-Domain Strategy:**

| Domain | DNS | Certificate | WAN Required |
|--------|-----|-------------|--------------|
| `*.lanmine.local` | OPNsense Unbound | Vault PKI | ❌ No |
| `*.hl0.dev` | OPNsense override | Let's Encrypt | ✅ Yes (initial) |
| `*.ts.net` | Tailscale | Let's Encrypt | ✅ Yes |

**Example Service (Grafana):**

```yaml
# Internal access (WAN-resilient)
- host: grafana.lanmine.local
  tls:
    secretName: grafana-lanmine-tls
    issuer: vault-issuer

# Public access (Cloudflare)
- host: grafana.hl0.dev
  tls:
    secretName: grafana-hl0-tls
    issuer: letsencrypt-prod

# Tailscale access (unchanged)
- host: grafana.lionfish-caiman.ts.net
  tls:
    secretName: grafana-ts-tls
    issuer: letsencrypt-prod
```

## Vault PKI Management

### Check Root CA
```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
vault read pki/cert/ca
```

### List Issued Certificates
```bash
vault list pki/certs
```

### Read Certificate Details
```bash
vault read pki/cert/<serial>
```

### Update PKI Role
```bash
vault write pki/roles/lanmine-local \
    allowed_domains="lanmine.local" \
    allow_subdomains=true \
    max_ttl="720h"
```

### Rotate AppRole Secret
```bash
# Generate new secret-id
NEW_SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/cert-manager/secret-id)

# Update Kubernetes secret
kubectl create secret generic vault-approle \
  --namespace=cert-manager \
  --from-literal=roleId=c61ed09d-43d8-7614-1456-b7c781c88723 \
  --from-literal=secretId=$NEW_SECRET_ID \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart cert-manager to pick up new secret
kubectl rollout restart deployment cert-manager -n cert-manager
```

## Testing

### Test Vault Issuer
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-vault
  namespace: default
spec:
  secretName: test-vault-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: test.lanmine.local
  dnsNames:
  - test.lanmine.local
EOF

# Check status
kubectl get certificate test-vault
kubectl describe certificate test-vault

# Verify issuer
kubectl get secret test-vault-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout | grep "Issuer:"
# Should show: Issuer: CN = Lanmine Internal Root CA

# Cleanup
kubectl delete certificate test-vault
```

### Verify Certificate Chain
```bash
# Get certificate
kubectl get secret <tls-secret> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/cert.pem

# Download Root CA
curl https://vault-01.lionfish-caiman.ts.net:8200/v1/pki/ca/pem > /tmp/ca.pem

# Verify chain
openssl verify -CAfile /tmp/ca.pem /tmp/cert.pem
# Should output: /tmp/cert.pem: OK
```

## Troubleshooting

### Certificate Not Issuing

**Check ClusterIssuer:**
```bash
kubectl get clusterissuer vault-issuer -o yaml
# Status should show Ready: True
```

**Check Certificate Status:**
```bash
kubectl describe certificate <name> -n <namespace>
# Look for Events showing approval/signing
```

**Check cert-manager Logs:**
```bash
kubectl logs -n cert-manager deployment/cert-manager | grep vault
```

**Verify Vault Connectivity:**
```bash
kubectl run vault-test --rm -it --image=curlimages/curl -- \
  curl -k https://vault-01.lionfish-caiman.ts.net:8200/v1/sys/health
```

### AppRole Authentication Failure

**Verify Secret Exists:**
```bash
kubectl get secret vault-approle -n cert-manager
```

**Test AppRole Login:**
```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
ROLE_ID=$(kubectl get secret vault-approle -n cert-manager -o jsonpath='{.data.roleId}' | base64 -d)
SECRET_ID=$(kubectl get secret vault-approle -n cert-manager -o jsonpath='{.data.secretId}' | base64 -d)

vault write auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID
# Should return a token
```

### Certificate Renewal Failing

**Check cert-manager Controller:**
```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager deployment/cert-manager
```

**Force Renewal:**
```bash
# Delete certificate secret (cert-manager will recreate)
kubectl delete secret <tls-secret> -n <namespace>

# Certificate will be re-issued automatically
kubectl get certificate <name> -n <namespace> -w
```

## Security Considerations

1. **AppRole Secret Rotation:** Rotate secret-id quarterly
2. **Root CA Protection:** Vault root token stored securely
3. **Network Access:** Vault accessible only from Kubernetes cluster
4. **Certificate Validity:** 30-day max reduces exposure window
5. **Audit Logging:** All certificate issuance logged in Vault

## Migration Path

### Phase 2a (Current): Vault PKI Available
- vault-issuer ClusterIssuer created
- Services can opt-in to Vault certificates
- Existing lanmine-ca-issuer still works

### Phase 2b (Future): Migrate Existing Services
- Update Grafana ingress to use vault-issuer
- Update NetBox ingress to use vault-issuer
- Update other *.lanmine.local services
- Keep lanmine-ca-issuer for backward compatibility

### Phase 2c (Optional): Decommission Old CA
- All services migrated to vault-issuer
- Remove lanmine-ca-issuer
- Archive old CA certificate

## Next Phase

**Phase 3: WAN Failover Testing**
- Test DNS failover (disconnect WAN cable)
- Test certificate validation during outage
- Verify all *.lanmine.local services accessible
- Document failover procedures
