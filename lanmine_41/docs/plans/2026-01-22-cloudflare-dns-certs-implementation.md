# Cloudflare DNS and Certificate Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy external-dns and cert-manager with Cloudflare integration to provide automatic DNS management and Let's Encrypt certificates for hl0.dev domain.

**Architecture:** external-dns watches Kubernetes Ingress resources and creates DNS records in Cloudflare. cert-manager uses Cloudflare DNS-01 challenge to obtain Let's Encrypt certificates. Both run parallel to existing Tailscale setup with no disruption.

**Tech Stack:** external-dns (registry.k8s.io/external-dns/external-dns:v0.15.0), cert-manager (existing), Cloudflare API, Let's Encrypt ACME, ExternalSecret (external-secrets-operator)

---

## Task 1: Create Cloudflare API Token Secret

**Files:**
- Create: `kubernetes/infrastructure/cert-manager/cloudflare-secret.yaml`

**Step 1: Create ExternalSecret for Cloudflare API token**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: cloudflare-api-token
    creationPolicy: Owner
  data:
  - secretKey: api-token
    remoteRef:
      key: secret/infrastructure/cloudflare
      property: api_token
```

**Step 2: Apply the ExternalSecret**

Run: `kubectl apply -f kubernetes/infrastructure/cert-manager/cloudflare-secret.yaml`
Expected: `externalsecret.external-secrets.io/cloudflare-api-token created`

**Step 3: Verify Secret was created**

Run: `kubectl get secret cloudflare-api-token -n cert-manager`
Expected: Secret exists with 1 data key

**Step 4: Commit**

```bash
git add kubernetes/infrastructure/cert-manager/cloudflare-secret.yaml
git commit -m "feat: add Cloudflare API token ExternalSecret for cert-manager"
```

---

## Task 2: Create Let's Encrypt ClusterIssuer

**Files:**
- Create: `kubernetes/infrastructure/cert-manager/letsencrypt-issuer.yaml`
- Modify: `kubernetes/infrastructure/cert-manager/kustomization.yaml`

**Step 1: Create Let's Encrypt production ClusterIssuer**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@hl0.dev
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

**Step 2: Update kustomization.yaml to include new resources**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrepository.yaml
  - cert-manager.yaml
  - cloudflare-secret.yaml
  - letsencrypt-issuer.yaml
```

**Step 3: Apply the ClusterIssuer**

Run: `kubectl apply -f kubernetes/infrastructure/cert-manager/letsencrypt-issuer.yaml`
Expected: `clusterissuer.cert-manager.io/letsencrypt-prod created`

**Step 4: Verify ClusterIssuer is Ready**

Run: `kubectl get clusterissuer letsencrypt-prod`
Expected: STATUS = Ready = True

**Step 5: Commit**

```bash
git add kubernetes/infrastructure/cert-manager/letsencrypt-issuer.yaml kubernetes/infrastructure/cert-manager/kustomization.yaml
git commit -m "feat: add Let's Encrypt production ClusterIssuer with Cloudflare DNS-01"
```

---

## Task 3: Create external-dns Namespace and RBAC

**Files:**
- Create: `kubernetes/infrastructure/external-dns/namespace.yaml`
- Create: `kubernetes/infrastructure/external-dns/serviceaccount.yaml`
- Create: `kubernetes/infrastructure/external-dns/clusterrole.yaml`
- Create: `kubernetes/infrastructure/external-dns/clusterrolebinding.yaml`

**Step 1: Create namespace**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
```

**Step 2: Create ServiceAccount**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
```

**Step 3: Create ClusterRole**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
```

**Step 4: Create ClusterRoleBinding**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: external-dns
```

**Step 5: Apply all RBAC resources**

Run: `kubectl apply -f kubernetes/infrastructure/external-dns/namespace.yaml -f kubernetes/infrastructure/external-dns/serviceaccount.yaml -f kubernetes/infrastructure/external-dns/clusterrole.yaml -f kubernetes/infrastructure/external-dns/clusterrolebinding.yaml`
Expected: All resources created

**Step 6: Commit**

```bash
git add kubernetes/infrastructure/external-dns/
git commit -m "feat: add external-dns namespace and RBAC"
```

---

## Task 4: Create external-dns Cloudflare Secret

**Files:**
- Create: `kubernetes/infrastructure/external-dns/externalsecret.yaml`

**Step 1: Create ExternalSecret for Cloudflare API token**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: cloudflare-api-token
    creationPolicy: Owner
  data:
  - secretKey: CF_API_TOKEN
    remoteRef:
      key: secret/infrastructure/cloudflare
      property: api_token
```

**Step 2: Apply the ExternalSecret**

Run: `kubectl apply -f kubernetes/infrastructure/external-dns/externalsecret.yaml`
Expected: `externalsecret.external-secrets.io/cloudflare-api-token created`

**Step 3: Verify Secret was created**

Run: `kubectl get secret cloudflare-api-token -n external-dns`
Expected: Secret exists with 1 data key (CF_API_TOKEN)

**Step 4: Commit**

```bash
git add kubernetes/infrastructure/external-dns/externalsecret.yaml
git commit -m "feat: add Cloudflare API token ExternalSecret for external-dns"
```

---

## Task 5: Deploy external-dns in Dry-Run Mode

**Files:**
- Create: `kubernetes/infrastructure/external-dns/deployment.yaml`

**Step 1: Create external-dns deployment (dry-run mode)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.15.0
        args:
        - --source=ingress
        - --source=service
        - --provider=cloudflare
        - --domain-filter=hl0.dev
        - --txt-owner-id=k8s-talos-cluster
        - --policy=sync
        - --registry=txt
        - --txt-prefix=_externaldns.
        - --log-level=debug
        - --dry-run=true
        env:
        - name: CF_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflare-api-token
              key: CF_API_TOKEN
        resources:
          requests:
            cpu: 10m
            memory: 50Mi
          limits:
            cpu: 100m
            memory: 100Mi
```

**Step 2: Apply the deployment**

Run: `kubectl apply -f kubernetes/infrastructure/external-dns/deployment.yaml`
Expected: `deployment.apps/external-dns created`

**Step 3: Verify pod is running**

Run: `kubectl get pods -n external-dns`
Expected: Pod STATUS = Running

**Step 4: Check logs for dry-run mode confirmation**

Run: `kubectl logs -n external-dns deployment/external-dns --tail=50`
Expected: Logs show "running in dry-run mode" and detection of existing ingresses

**Step 5: Commit**

```bash
git add kubernetes/infrastructure/external-dns/deployment.yaml
git commit -m "feat: deploy external-dns in dry-run mode for testing"
```

---

## Task 6: Create external-dns Kustomization

**Files:**
- Create: `kubernetes/infrastructure/external-dns/kustomization.yaml`
- Modify: `kubernetes/infrastructure/kustomization.yaml`

**Step 1: Create external-dns kustomization**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - serviceaccount.yaml
  - clusterrole.yaml
  - clusterrolebinding.yaml
  - externalsecret.yaml
  - deployment.yaml
```

**Step 2: Update infrastructure kustomization to include external-dns**

Run: `grep -q "external-dns" kubernetes/infrastructure/kustomization.yaml || echo "  - external-dns" >> kubernetes/infrastructure/kustomization.yaml`
Expected: external-dns added to resources list

**Step 3: Test kustomization builds**

Run: `kubectl kustomize kubernetes/infrastructure/external-dns/`
Expected: All manifests printed without errors

**Step 4: Commit**

```bash
git add kubernetes/infrastructure/external-dns/kustomization.yaml kubernetes/infrastructure/kustomization.yaml
git commit -m "feat: add external-dns kustomization and integrate with infrastructure"
```

---

## Task 7: Verify Dry-Run Mode Behavior

**Files:**
- None (verification only)

**Step 1: Check external-dns logs for Ingress detection**

Run: `kubectl logs -n external-dns deployment/external-dns | grep -i "ingress"`
Expected: Logs show detected Tailscale ingresses (grafana-tailscale, argocd-tailscale, etc.)

**Step 2: Verify no DNS records created in Cloudflare**

Run: `curl -s -X GET "https://api.cloudflare.com/client/v4/zones/283c74f5bfbbb2a804dabdb938ccde8f/dns_records" -H "Authorization: Bearer $(kubectl get secret cloudflare-api-token -n external-dns -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d)" | jq -r '.result | length'`
Expected: Count = 0 (no records created yet)

**Step 3: Verify external-dns dry-run logs show what WOULD be created**

Run: `kubectl logs -n external-dns deployment/external-dns | grep -i "would"`
Expected: Logs show "would create" or "would update" messages (but no actual changes)

**Step 4: Document verification results**

Create note: Dry-run mode working correctly, detecting ingresses but not creating DNS records.

---

## Task 8: Enable external-dns Live Mode

**Files:**
- Modify: `kubernetes/infrastructure/external-dns/deployment.yaml:28`

**Step 1: Remove dry-run flag from deployment**

Change line 28 from:
```yaml
        - --dry-run=true
```
To: (remove the line entirely)

**Step 2: Apply updated deployment**

Run: `kubectl apply -f kubernetes/infrastructure/external-dns/deployment.yaml`
Expected: `deployment.apps/external-dns configured`

**Step 3: Wait for pod to restart**

Run: `kubectl rollout status deployment/external-dns -n external-dns --timeout=60s`
Expected: `deployment "external-dns" successfully rolled out`

**Step 4: Verify live mode in logs**

Run: `kubectl logs -n external-dns deployment/external-dns --tail=20 | grep -v "dry-run"`
Expected: No "dry-run mode" messages, logs show actual operations

**Step 5: Commit**

```bash
git add kubernetes/infrastructure/external-dns/deployment.yaml
git commit -m "feat: enable external-dns live mode to create DNS records"
```

---

## Task 9: Create Test Ingress for Grafana

**Files:**
- Create: `kubernetes/apps/monitoring/grafana-ingress-cloudflare.yaml`

**Step 1: Create Grafana Cloudflare Ingress**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-cloudflare
  namespace: monitoring
  annotations:
    external-dns.alpha.kubernetes.io/hostname: grafana.hl0.dev
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - grafana.hl0.dev
    secretName: grafana-hl0-tls
  rules:
  - host: grafana.hl0.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
```

**Step 2: Apply the Ingress**

Run: `kubectl apply -f kubernetes/apps/monitoring/grafana-ingress-cloudflare.yaml`
Expected: `ingress.networking.k8s.io/grafana-cloudflare created`

**Step 3: Watch external-dns logs for DNS record creation**

Run: `kubectl logs -n external-dns deployment/external-dns --tail=50 -f`
Expected: Logs show "CREATE" operation for grafana.hl0.dev A record

**Step 4: Verify DNS record in Cloudflare**

Run: `curl -s -X GET "https://api.cloudflare.com/client/v4/zones/283c74f5bfbbb2a804dabdb938ccde8f/dns_records?name=grafana.hl0.dev" -H "Authorization: Bearer $(kubectl get secret cloudflare-api-token -n external-dns -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d)" | jq -r '.result[] | {name:.name, type:.type, content:.content}'`
Expected: A record pointing to 10.0.10.40

**Step 5: Commit**

```bash
git add kubernetes/apps/monitoring/grafana-ingress-cloudflare.yaml
git commit -m "feat: add Cloudflare Ingress for Grafana with Let's Encrypt cert"
```

---

## Task 10: Verify Certificate Issuance

**Files:**
- None (verification only)

**Step 1: Check Certificate resource was created**

Run: `kubectl get certificate -n monitoring grafana-hl0-tls`
Expected: Certificate exists

**Step 2: Check Certificate status**

Run: `kubectl describe certificate -n monitoring grafana-hl0-tls | grep -A 5 "Status:"`
Expected: Ready = True (may take 1-2 minutes)

**Step 3: Watch cert-manager logs for DNS-01 challenge**

Run: `kubectl logs -n cert-manager deployment/cert-manager --tail=100 | grep -i "dns\|challenge\|grafana"`
Expected: Logs show DNS-01 challenge created, validated, and certificate issued

**Step 4: Verify TXT record was created and deleted**

Run: `curl -s -X GET "https://api.cloudflare.com/client/v4/zones/283c74f5bfbbb2a804dabdb938ccde8f/dns_records?name=_acme-challenge.grafana.hl0.dev" -H "Authorization: Bearer $(kubectl get secret cloudflare-api-token -n external-dns -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d)" | jq -r '.result | length'`
Expected: Count = 0 (TXT record cleaned up after challenge)

**Step 5: Verify TLS Secret was created**

Run: `kubectl get secret grafana-hl0-tls -n monitoring -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates`
Expected: Valid Let's Encrypt certificate for grafana.hl0.dev

---

## Task 11: Test DNS Resolution and HTTPS Access

**Files:**
- None (verification only)

**Step 1: Test DNS resolution from LAN**

Run: `dig +short grafana.hl0.dev`
Expected: 10.0.10.40

**Step 2: Test HTTPS connectivity**

Run: `curl -I https://grafana.hl0.dev`
Expected: HTTP/2 200, no certificate errors

**Step 3: Verify certificate chain**

Run: `curl -vI https://grafana.hl0.dev 2>&1 | grep -A 3 "issuer:"`
Expected: Issuer = Let's Encrypt Authority

**Step 4: Test browser access (manual)**

Open: https://grafana.hl0.dev
Expected: Valid HTTPS connection, Grafana loads correctly

**Step 5: Verify Tailscale ingress still works**

Run: `curl -I https://grafana.lionfish-caiman.ts.net`
Expected: HTTP/2 200 (dual-access working)

---

## Task 12: Create ArgoCD Application for external-dns

**Files:**
- Create: `kubernetes/infrastructure/argocd/applications/external-dns.yaml`
- Modify: `kubernetes/infrastructure/argocd/applications/kustomization.yaml`

**Step 1: Create ArgoCD Application**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Lanmine/lanmine_tech
    targetRevision: main
    path: kubernetes/infrastructure/external-dns
  destination:
    server: https://kubernetes.default.svc
    namespace: external-dns
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Step 2: Update applications kustomization**

Add to `kubernetes/infrastructure/argocd/applications/kustomization.yaml`:
```yaml
  - external-dns.yaml
```

**Step 3: Apply ArgoCD Application**

Run: `kubectl apply -f kubernetes/infrastructure/argocd/applications/external-dns.yaml`
Expected: `application.argoproj.io/external-dns created`

**Step 4: Verify ArgoCD manages external-dns**

Run: `kubectl get application -n argocd external-dns`
Expected: SYNC STATUS = Synced, HEALTH STATUS = Healthy

**Step 5: Commit**

```bash
git add kubernetes/infrastructure/argocd/applications/external-dns.yaml kubernetes/infrastructure/argocd/applications/kustomization.yaml
git commit -m "feat: add ArgoCD Application for external-dns"
```

---

## Task 13: Update CLAUDE.md Documentation

**Files:**
- Modify: `CLAUDE.md` (add Cloudflare DNS section after Tailscale section)

**Step 1: Add Cloudflare DNS documentation**

Insert after Tailscale section (around line 220):

```markdown
### Cloudflare DNS (hl0.dev)

DNS management and Let's Encrypt certificates for hl0.dev domain via Cloudflare.

**Components:**
- **external-dns**: Automatic DNS record creation in Cloudflare
- **cert-manager**: Let's Encrypt certificates via DNS-01 challenge
- **Domain**: hl0.dev (public DNS, private IPs)

**Configuration:**
- Cloudflare token: Vault at `secret/infrastructure/cloudflare`
- Zone ID: 283c74f5bfbbb2a804dabdb938ccde8f
- DNS records point to Traefik LoadBalancer (10.0.10.40)

**Creating Cloudflare Ingresses:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: service-cloudflare
  namespace: <namespace>
  annotations:
    external-dns.alpha.kubernetes.io/hostname: service.hl0.dev
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - service.hl0.dev
    secretName: service-hl0-tls
  rules:
  - host: service.hl0.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <service-name>
            port:
              number: <port>
```

**Dual-Access Pattern:**
- Services maintain both Tailscale AND Cloudflare ingresses
- Tailscale: `*.lionfish-caiman.ts.net` (unchanged)
- Cloudflare: `*.hl0.dev` (new, parallel)

**Certificate Management:**
- Automatic issuance via Let's Encrypt (90-day validity)
- Auto-renewal at 60 days
- ClusterIssuer: `letsencrypt-prod`
```

**Step 2: Commit documentation**

```bash
git add CLAUDE.md
git commit -m "docs: add Cloudflare DNS and certificate management to CLAUDE.md"
```

---

## Task 14: Final Validation and Testing

**Files:**
- None (validation only)

**Step 1: Run local tests**

Run: `./test-local.sh --quick`
Expected: All tests pass

**Step 2: Verify all resources are healthy**

Run: `kubectl get all -n external-dns && kubectl get clusterissuer && kubectl get certificate -A`
Expected: All resources Running/Ready

**Step 3: Verify DNS records in Cloudflare**

Run: `curl -s -X GET "https://api.cloudflare.com/client/v4/zones/283c74f5bfbbb2a804dabdb938ccde8f/dns_records" -H "Authorization: Bearer $(kubectl get secret cloudflare-api-token -n external-dns -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d)" | jq -r '.result[] | {name:.name, type:.type, content:.content}'`
Expected: grafana.hl0.dev A record and TXT records for external-dns ownership

**Step 4: Test certificate auto-renewal behavior**

Run: `kubectl describe certificate -n monitoring grafana-hl0-tls | grep "Renewal Time"`
Expected: Renewal scheduled for 60 days from issuance

**Step 5: Create implementation summary**

Document:
- ✅ external-dns deployed and creating DNS records
- ✅ Let's Encrypt ClusterIssuer configured
- ✅ Grafana accessible at https://grafana.hl0.dev
- ✅ Dual-access working (Tailscale + Cloudflare)
- ✅ ArgoCD managing external-dns
- ✅ Documentation updated

---

## Success Criteria

- [x] external-dns automatically creates DNS records for annotated Ingresses
- [x] DNS records resolve to Traefik LoadBalancer IP (10.0.10.40)
- [x] cert-manager successfully issues Let's Encrypt certificates via DNS-01
- [x] Certificates auto-renew before expiry
- [x] Services accessible via both Tailscale and Cloudflare DNS URLs
- [x] No disruption to existing Tailscale ingresses

## Rollback Plan

If issues occur:
1. Delete external-dns: `kubectl delete -k kubernetes/infrastructure/external-dns/`
2. Manually remove DNS records from Cloudflare
3. Delete Cloudflare ingresses: `kubectl delete ingress grafana-cloudflare -n monitoring`
4. Tailscale ingresses remain unaffected

## Next Steps

After successful implementation:
1. Create Cloudflare Ingresses for other services (ArgoCD, Prometheus, etc.)
2. Consider wildcard certificate for `*.hl0.dev`
3. Monitor certificate renewals
4. Update other service documentation with hl0.dev URLs
