# VM Certificate Status for WAN Resilience

## Summary

VMs outside Kubernetes cluster with HTTPS services that need WAN-resilient certificates for `.lanmine.local` domains.

## Services Requiring Certificate Updates

### 1. OPNsense (10.0.10.1:443)
**Status**: ⚠️ Certificate needs update
**Current**: Let's Encrypt certificate for `opnsense.lionfish-caiman.ts.net` only
**Required**: Certificate with both `opnsense.lanmine.local` and `opnsense.lionfish-caiman.ts.net`
**Certificate Generated**: ✓ Yes (`/tmp/opnsense.crt`, `/tmp/opnsense.key`)
**Installed**: ❌ No - requires Web UI or API upload

**Installation Method**:
- Option 1: Upload via Web UI (System → Trust → Certificates)
- Option 2: Use OPNsense API to import certificate
- Option 3: Modify `/conf/config.xml` directly (risky)

**Certificate Details**:
```
Subject: CN=opnsense.lanmine.local
SANs: opnsense.lanmine.local, opnsense.lionfish-caiman.ts.net
Issuer: Lanmine Internal Root CA
Validity: 8760h (1 year)
```

### 2. Authentik (10.0.10.25:9443)
**Status**: ⚠️ Certificate generated but not active
**Current**: Using Authentik default self-signed certificate
**Required**: Certificate with both `authentik.lanmine.local` and `authentik-01.lionfish-caiman.ts.net`
**Certificate Generated**: ✓ Yes
**Files Updated**: ✓ Yes (`/opt/authentik/certs/`)
**Installed**: ❌ No - Authentik not loading files, using default cert

**Issue**: Authentik appears to manage certificates through its "Brand" system in the Web UI/database rather than reading from environment variable file paths. The certificate files were updated correctly, but Authentik is still serving its default certificate.

**Certificate Details**:
```
Subject: CN=authentik.lanmine.local
SANs: authentik-01.lionfish-caiman.ts.net, authentik.lanmine.local
Issuer: Lanmine Internal Root CA
Validity: 8760h (1 year)
Location: /opt/authentik/certs/authentik-01.lionfish-caiman.ts.net.{crt,key}
```

**Files in Container**:
- `/certs/authentik-01.lionfish-caiman.ts.net.crt` - ✓ Has correct SANs
- `/certs/authentik-01.lionfish-caiman.ts.net.key` - ✓ Present
- Backup files created with timestamp

**Next Steps for Authentik**:
1. Research Authentik brand certificate configuration
2. Upload certificate via Authentik Admin UI (System → Certificates)
3. Configure brand to use uploaded certificate
4. Alternative: Set environment variable to disable brand certificate management

### 3. n8n (10.0.10.27:5678)
**Status**: ✅ No action needed
**Current**: HTTP only
**Access**: Via Kubernetes ingress (https://n8n.lanmine.local through Traefik at 10.0.10.40)
**Note**: Certificate handled by cert-manager in Kubernetes cluster

### 4. Akvorado (10.0.10.26:8080)
**Status**: ✅ No action needed
**Current**: HTTP only
**Access**: Via Kubernetes ingress (https://akvorado.lanmine.local through Traefik at 10.0.10.40)
**Note**: Certificate handled by cert-manager in Kubernetes cluster

### 5. Vault (10.0.10.21:8200)
**Status**: ✅ Complete
**Current**: Vault PKI certificate with both domains
**SANs**: vault.lanmine.local, vault-01.lionfish-caiman.ts.net
**Verification**: Working via both domains without TLS errors

## Vault PKI Role

Created `vault-server` role for infrastructure services:
```
Path: pki/roles/vault-server
Allowed domains: lanmine.local, lionfish-caiman.ts.net
Allow subdomains: true
Max TTL: 8760h (1 year)
```

## Certificate Files Location

All generated certificates are in `/tmp/` on ubuntu-mgmt01:
- `/tmp/opnsense.crt` + `/tmp/opnsense.key` - Ready for OPNsense installation
- `/tmp/authentik.crt` + `/tmp/authentik.key` - Copied to Authentik VM but not active

## Next Actions

1. **OPNsense**: Install certificate via Web UI or API
2. **Authentik**: Configure brand certificates to use uploaded cert files
3. **Testing**: Verify HTTPS access via `.lanmine.local` domains works without TLS errors
4. **Documentation**: Update CLAUDE.md with certificate renewal procedures
