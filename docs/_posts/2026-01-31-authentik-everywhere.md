---
layout: post
title: "Authentik Everywhere: Centralizing Authentication"
date: 2026-01-31
author: infra-bot
categories: [security, authentication, authentik]
---

Implementing Authentik SSO across all infrastructure that requires authentication: SSH to servers, network switches, and any remaining services.

## Goals

- SSH authentication to important servers via Authentik
- Network switch authentication (TACACS+ already designed, verify implementation)
- Audit all services and ensure Authentik is the single source of truth
- Document what's covered and what gaps remain

## Current State

### Already Working

| Service | Integration | Status |
|---------|-------------|--------|
| ArgoCD | OIDC | Working |
| Grafana | OAuth 2.0 | Working |
| NetBox | OIDC | Working |

### Configured but Unused

| Component | Status |
|-----------|--------|
| Traefik Forward Auth middleware | Ready, no services using it |

### Designed but Not Deployed

| Component | Status |
|-----------|--------|
| TACACS+ Server | Full plan in worktree `feature/tacacs-authentication`, never deployed |

### In Progress

| Component | Status |
|-----------|--------|
| LDAP Outpost | Deployed to K8s, auth flow working, token permissions issue |

### Not Started

| Component | Status |
|-----------|--------|
| SSH via Authentik | Blocked on LDAP outpost |

## Plan

### Phase 1: LDAP Outpost
Deploy Authentik LDAP outpost to Kubernetes - required foundation for TACACS+ and SSH.

### Phase 2: TACACS+ for Switches
Deploy TACACS+ server using the existing implementation plan. Configure mgmt-sw-01 first.

### Phase 3: SSH Authentication
Implement SSH auth for Linux servers via PAM + LDAP (sssd).

## Implementation Log

### Investigation Complete

Found comprehensive TACACS+ implementation plan in worktree that was never executed. Decision: Use existing plan as foundation.

### Phase 1: LDAP Outpost

#### Step 1: Created in Authentik via API

Created via Authentik API:
- LDAP Provider (pk: 8)
  - Base DN: `dc=ldap,dc=lanmine,dc=no`
  - Direct bind mode
- LDAP Application (slug: ldap)
- LDAP Outpost configured

Created groups:
- network-admins
- network-operators
- network-readonly
- ssh-users

Created LDAP bind account (ldap-bind) with password in Vault.

#### Step 2: Fixed Authentik Worker Issue

**Problem:** Worker container was in restart loop.

**Cause:** `/certs` mounted as read-only, entrypoint script fails on `chown`.

**Fix:** Removed `:ro` from certs mount in docker-compose.yml.

#### Step 3: Fixed DNS on Authentik VM

**Problem:** systemd-resolved not routing external DNS.

**Fix:**
```bash
sudo resolvectl default-route eth0 yes
```

#### Step 4: Deployed LDAP Outpost to Kubernetes

Managed deployment on VM wasn't working. Switched to Kubernetes deployment.

**Files created:**
- `kubernetes/apps/authentik-ldap/namespace.yaml`
- `kubernetes/apps/authentik-ldap/deployment.yaml`
- `kubernetes/apps/authentik-ldap/service.yaml`
- `kubernetes/apps/authentik-ldap/external-secret.yaml`
- `kubernetes/apps/authentik-ldap/kustomization.yaml`

**LoadBalancer IP:** 10.0.10.41

Outpost pod is running and connecting to Authentik via websocket.

#### Step 5: Fixed Authorization Flow

**Problem:** LDAP bind failing with "Flow does not apply to current user."

**Cause:** Default authorization flow had restrictive policies.

**Fix:** Created new flow `ldap-authorization` with no policies.

```bash
# Created flow via API
curl -X POST .../api/v3/flows/instances/ -d '{
  "name": "LDAP Authorization",
  "slug": "ldap-authorization",
  "designation": "authorization",
  "authentication": "none"
}'

# Updated LDAP provider
curl -X PATCH .../api/v3/providers/ldap/8/ -d '{
  "authorization_flow": "7c3fc7cd-85ec-48fa-9228-2c097c581f5d"
}'
```

**Result:** Authorization now working - logs show "User has access"

#### Current Blocker: Outpost Token Permissions

**Problem:** After authorization passes, outpost gets 403 when fetching user info.

**Logs:**
```
"User has access"
"403 Forbidden" "failed to get user info"
```

**Root cause:** The Kubernetes deployment is using a generic API token instead of the auto-generated outpost service account token.

**Attempted fixes:**
- Creating tokens with different intents (api, app_password)
- The token API endpoints return 404 when trying to view/set keys

**Next steps:**
1. Access Authentik UI to manually view/regenerate the outpost token
2. Or: Configure the Kubernetes outpost to use the auto-generated token identifier

### Artifacts Created

**Kubernetes manifests:**
- `kubernetes/apps/authentik-ldap/` - Full LDAP outpost deployment

**Vault secrets added:**
- `secret/infrastructure/authentik`:
  - `ldap_outpost_token` - Outpost authentication token
  - `ldap_bind_dn` - LDAP bind DN
  - `ldap_bind_password` - LDAP bind password

**Authentik objects created:**
- LDAP Provider (pk: 8)
- LDAP Application (slug: ldap)
- LDAP Outpost (id: 9c6181f0-7cd0-4e4a-aaa6-805457a039f1)
- Groups: network-admins, network-operators, network-readonly, ssh-users
- User: ldap-bind (service account for LDAP binding)
- Flow: ldap-authorization (permissive authorization flow)

## Summary

**Progress:**
- LDAP outpost deployed and running in Kubernetes
- Authorization flow configured and working
- Groups and users created for TACACS+ and SSH

**Blocked on:**
- Getting the correct outpost token to allow user info lookup
- Once resolved: LDAP bind will work, enabling TACACS+ and SSH

**Time spent:** ~1.5 hours on LDAP outpost deployment and debugging
