# VM Certificate Status for WAN Resilience

## Summary

Status of VMs outside Kubernetes cluster with HTTPS services requiring WAN-resilient certificates for `.lanmine.local` domains.

**Completed**: Vault, OPNsense, Authentik ✅
**All services now use Vault PKI certificates with WAN-resilient SANs**

## Services Requiring Certificate Updates

### 1. OPNsense (10.0.10.1:443)
**Status**: ✅ Complete
**Current**: Vault PKI certificate for both `opnsense.lanmine.local` and `opnsense.lionfish-caiman.ts.net`
**Certificate Generated**: ✓ Yes
**Installed**: ✓ Yes (via config.xml modification + lighttpd reload)

**Certificate Details**:
```
Subject: CN=opnsense.lanmine.local
SANs: opnsense.lanmine.local, opnsense.lionfish-caiman.ts.net
Issuer: Lanmine Internal Root CA
Validity: 8760h (1 year)
UUID: 64967b5f-dcc8-4f43-ae85-42a1093b9dfd
Refid: 6974d713210a
```

**Installation Details**:
- Certificate added to `/conf/config.xml`
- Backup: `/conf/config.xml.pre-vault-cert-20260124-152835`
- Lighttpd cert files: `/usr/local/etc/lighttpd_webgui/{cert.pem,key.pem}`
- Lighttpd backup: `/usr/local/etc/lighttpd_webgui/cert.pem.backup-20260124-153049`

### 2. Authentik (10.0.10.25:9443)
**Status**: ✅ Complete
**Current**: Vault PKI certificate for both `authentik.lanmine.local` and `authentik-01.lionfish-caiman.ts.net`
**Certificate Generated**: ✓ Yes
**Installed**: ✓ Yes (via Authentik API + Brand configuration)

**Certificate Details**:
```
Subject: CN=authentik.lanmine.local
SANs: authentik-01.lionfish-caiman.ts.net, authentik.lanmine.local
Issuer: Lanmine Internal Root CA
Validity: 8760h (1 year)
Certificate UUID: 08965095-3670-4a62-990a-51efb49cae9f
Brand UUID: 3eeeb010-291c-4fb1-a7b9-6550f6d80623
```

**Installation Method**:
- Uploaded certificate via Authentik API (`/api/v3/crypto/certificatekeypairs/`)
- Configured default brand to use certificate via PATCH to `/api/v3/core/brands/`
- Environment variable `AUTHENTIK_LISTEN__DISABLE_BRAND_TLS=true` added to .env (currently not required but recommended)
- Restarted Authentik server to apply changes

**Why Environment Variables Alone Didn't Work**:
Authentik's "Brand TLS" feature manages certificates through its database, not directly from environment variable file paths. The `AUTHENTIK_LISTEN__SSL__CERTIFICATE` environment variable is only used when brand TLS is disabled or when no brand certificate is configured. The correct approach is to upload the certificate via the API and assign it to the brand.

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

1. **Testing**: Verify HTTPS access to all services via `.lanmine.local` domains ✅
2. **Documentation**: Update CLAUDE.md with certificate renewal procedures
3. **Automation**: Create Ansible playbook for certificate renewal from Vault PKI
4. **Monitoring**: Set up alerts for certificate expiration (certificates expire in 1 year)
