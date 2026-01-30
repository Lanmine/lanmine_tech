# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is infrastructure-as-code for Lanmine.no, managing Proxmox VE virtual machines via Terraform, with Ansible for configuration backups. Secrets are managed through HashiCorp Vault.

## Token Conservation

Be conservative with token usage:
- Keep responses concise and to the point
- Avoid verbose explanations unless asked
- Use tables and bullet points over paragraphs
- Don't repeat information already shown in tool output
- Skip unnecessary confirmations and preamble
- Prefer targeted file reads over reading entire files when possible

## Key Commands

### Terraform

```bash
# Load secrets from Vault into environment
cd terraform && source load_tf_secrets.sh

# Initialize with PostgreSQL backend (state stored in Vault-managed PG)
terraform init -backend-config="conn_str=${PG_CONN_STR}"

# Standard workflow
terraform plan
terraform apply
```

### Pre-commit Validation

```bash
# Run local validation before pushing (avoids CI failures)
./test-local.sh           # Standard checks
./test-local.sh --quick   # Syntax only
./test-local.sh --full    # Full test including terraform plan
```

### Ansible Backups

```bash
cd ansible
ansible-playbook playbooks/backup-all.yml
```

## Architecture

### Terraform (`terraform/`)

- **Provider**: bpg/proxmox for Proxmox VE
- **Backend**: PostgreSQL (connection string from Vault at `secret/infrastructure/postgres`)
- **VM inventory**: Defined in `main.tf` `locals.vms` map - single source of truth for all VMs
- **State protection**: All VMs have `prevent_destroy = true` and ignore cloud-init drift

Secrets loaded via `load_tf_secrets.sh`:
- `secret/infrastructure/proxmox` - API credentials
- `secret/infrastructure/ssh` - SSH public key for cloud-init

### Ansible (`ansible/`)

**Roles:**
| Role | Purpose |
|------|---------|
| `opnsense_backup` | Backup OPNsense config, encrypt with age |
| `proxmox_backup` | Backup Proxmox config, encrypt with age |
| `vault_backup` | Vault file storage backup, encrypt with age |
| `postgres_backup` | PostgreSQL pg_dump, encrypt with age |
| `rsyslog_forward` | Configure rsyslog to forward logs to Loki |
| `akvorado_install` | Install Akvorado flow collector via Docker (30-day TTL) |
| `lancache_install` | Install LANcache game download cache via Docker |
| `n8n_install` | Install n8n workflow automation via Docker |
| `journald_config` | Configure journald log rotation (2GB max, 30 days) |

**Playbooks:**
| Playbook | Purpose |
|----------|---------|
| `backup-all.yml` | Run all backup roles, commit to git |
| `configure-rsyslog.yml` | Configure syslog forwarding on linux_vms |
| `deploy-akvorado.yml` | Install and configure Akvorado |
| `deploy-lancache.yml` | Install and configure LANcache |
| `deploy-n8n.yml` | Install and configure n8n |
| `deploy-n8n-workflows.yml` | Deploy n8n workflows from JSON files |
| `configure-journald.yml` | Configure journald log rotation on linux_vms |

**Inventory Sources:**
- `inventory/hosts.yml` - Static inventory for infrastructure VMs
- `inventory/netbox.netbox.yml` - Dynamic inventory from NetBox (network devices)

NetBox dynamic inventory automatically pulls switches and network devices with their metadata, creating groups by manufacturer, role, site, and device type. Requires `NETBOX_TOKEN` environment variable:
```bash
export VAULT_ADDR="https://vault-01.lionfish-caiman.ts.net:8200"
export NETBOX_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)
ansible-inventory --list  # Shows combined inventory
```

**Host Groups:**
- `infrastructure` - All infrastructure hosts (static)
- `linux_vms` - Linux VMs with rsyslog (vault, runner, authentik, postgres, akvorado, n8n)
- `n8n_servers` - n8n workflow automation servers
- `lancache_servers` - LANcache servers (ubuntu-mgmt02)
- `cisco_switches` - All Cisco network switches (NetBox dynamic + connection vars)
- `manufacturers_cisco` - Cisco devices from NetBox (auto-generated)
- `device_roles_access` - Access switches from NetBox (auto-generated)

**Secrets**:
- Vault integration via `group_vars/all/vault.yml`
- SSH usernames stored in Vault at `secret/infrastructure/ssh`
- Switch credentials at `secret/infrastructure/switches/global`
- NetBox API token at `secret/infrastructure/netbox`
- Backups stored in `ansible/backups/`, encrypted `.age` files committed to git

### GitHub Actions (`.github/workflows/`)

- `terraform-check.yml` - PR validation with plan output as comment
- `infrastructure-backup.yml` - Scheduled backups
- `vault-deploy.yml` - Vault deployment automation

All workflows authenticate to Vault via AppRole using repository secrets: `VAULT_ADDR`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`.

## Infrastructure Hosts

| Host | IP | Purpose |
|------|-----|---------|
| proxmox | 10.0.10.5 | Proxmox VE hypervisor |
| opnsense | 10.0.10.1 | Firewall/gateway |
| vault-01 | 10.0.10.21 | HashiCorp Vault (file storage backend) |
| runner-01 | 10.0.10.22 | GitHub Actions self-hosted runner |
| postgres-01 | 10.0.10.23 | PostgreSQL (Terraform state backend) |
| authentik-01 | 10.0.10.25 | Authentik SSO and Identity Provider |
| akvorado-01 | 10.0.10.26 | Akvorado network flow collector |
| n8n-01 | 10.0.10.27 | n8n workflow automation |
| talos-cp-01 | 10.0.10.30 | Talos Kubernetes control plane |
| talos-bdg-qhb | 10.0.10.102 | Talos Kubernetes worker |
| ubuntu-mgmt02 | 10.0.20.2 | LANcache server (Dell R630, VLAN 20) |

## Kubernetes Cluster

- **Distribution**: Talos Linux
- **CNI**: Cilium with Hubble observability
- **Ingress**: Traefik (LoadBalancer IP: 10.0.10.40)
- **GitOps**: ArgoCD v3.2.5
- **Monitoring**: kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
- **Certificates**: cert-manager with internal CA (lanmine-ca-issuer)
- **Load Balancer**: MetalLB (IP range: 10.0.10.40-10.0.10.49)
- **Storage**: Longhorn (distributed, replicated), local-path-provisioner (fallback)
- **Remote Access**: Tailscale Operator with Let's Encrypt HTTPS

### Tailscale Services

| Service | URL |
|---------|-----|
| ArgoCD | https://argocd.lionfish-caiman.ts.net |
| Glance | https://glance.lionfish-caiman.ts.net |
| Grafana | https://grafana.lionfish-caiman.ts.net |
| Alertmanager | https://alertmanager.lionfish-caiman.ts.net |
| Akvorado | https://akvorado.lionfish-caiman.ts.net |
| n8n | https://n8n.lionfish-caiman.ts.net |
| Traefik | https://traefik.lionfish-caiman.ts.net/dashboard/ |
| Hubble UI | https://hubble.lionfish-caiman.ts.net |
| Uptime Kuma | https://uptime.lionfish-caiman.ts.net |
| Panda9000 | https://panda.lionfish-caiman.ts.net |

### NetBox (Network Inventory)

NetBox is the source of truth for network infrastructure inventory, IPAM, and DCIM.

**Access:**
- Tailscale: https://netbox.lionfish-caiman.ts.net
- Cloudflare: https://netbox.hl0.dev
- API: https://netbox.hl0.dev/api/

**Credentials:** Vault at `secret/infrastructure/netbox`

**Components:**
- Database: PostgreSQL on postgres-01 (10.0.10.23)
- Cache: Redis in netbox namespace
- Storage: emptyDir (media/static)

**Integration:**

**Ansible Dynamic Inventory** (active):
- Configuration: `ansible/inventory/netbox.netbox.yml`
- Auto-discovers switches with primary IPs
- Creates groups: manufacturers_*, device_roles_*, device_types_*, sites_*
- Keyed group `cisco_switches` for all Cisco devices
- Connection vars from `ansible/inventory/hosts.yml` cisco_switches group

**Planned Integrations:**
- Oxidized: Device list via API for config backups
- SNMP exporter: Target discovery for monitoring
- ZTP: Switch registration post-provisioning

**Registered Devices:**
- mgmt-sw-01 (10.0.99.101) - Catalyst 2960X access switch

### Grafana Authentication

Grafana uses Authentik OAuth for SSO. Configuration:
- OAuth credentials stored in Vault at `secret/infrastructure/authentik`
- Kubernetes secret `grafana-oauth` in monitoring namespace
- Browser redirects go to Tailscale URL, server-side calls use LAN IP (10.0.10.25:9000)

### ArgoCD (GitOps)

ArgoCD manages application deployments with automated sync and self-healing.

**Installation:**
- Manifests: `kubernetes/infrastructure/argocd/`
- Installed via: `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.5/manifests/install.yaml`
- Version: v3.2.5

**Managed Applications:**
- `glance` - Dashboard at kubernetes/apps/glance
- `panda9000` - Panda cam viewer at kubernetes/apps/panda9000
- `uptime-kuma` - Uptime monitoring at kubernetes/apps/uptime-kuma

**Application Configuration:**
- All apps use automated sync with prune and self-heal enabled
- Source repo: https://github.com/Lanmine/lanmine_tech
- Applications defined in: `kubernetes/infrastructure/argocd/applications/`

**Access:** https://argocd.lionfish-caiman.ts.net

### Cilium (CNI)

Cilium provides networking, security, and observability with eBPF.

**Configuration:**
- HelmRelease: `kubernetes/infrastructure/cilium/cilium.yaml`
- Helm chart: cilium/cilium v1.16.5
- Native routing mode (no VXLAN tunnel)
- Hubble UI enabled for flow observability

**Talos Compatibility:**
- Sysctlfix disabled (Talos immutable /etc)
- Privileged init containers enabled
- Empty sysctl.d volume mounted

**Features:**
- Network policy enforcement
- Service mesh capabilities
- Hubble flow visualization at https://hubble.lionfish-caiman.ts.net

### OPNsense Monitoring

OPNsense firewall monitoring integrated with Prometheus and Grafana.

**Components:**
- **OS Node Exporter** (on OPNsense): System metrics at 10.0.10.1:9100
- **OPNsense API Exporter** (Kubernetes): Firewall-specific metrics via API
- **ServiceMonitors**: Two monitors for API and node exporter endpoints
- **Grafana Dashboards**: Pre-built dashboards for overview and system metrics

**Configuration:**
- Application: `kubernetes/apps/opnsense-exporter/`
- Secrets: Vault at `secret/infrastructure/opnsense`
- Scrape interval: 30s for both exporters

**Metrics Collected:**
- System: CPU, memory, disk, network interfaces
- Firewall: Gateway status, service health, Unbound DNS statistics
- CARP: Failover status (if configured)

**Access:** Dashboards in Grafana (https://grafana.lionfish-caiman.ts.net)

### Infrastructure Monitoring

Comprehensive monitoring stack with 100% device coverage (12/12 devices).

**Architecture:**
- **SNMP**: 9 devices (8 Linux VMs + 1 switch + 1 firewall)
- **node-exporter**: 3 Kubernetes nodes (Talos)
- **Uptime Kuma**: 16 monitors (HTTP + ICMP)
- **Prometheus**: 42 active targets
- **Alerting**: 16 rules with email notifications

**SNMP Monitoring:**

*Linux VMs (8 devices):*
- Deployed via Ansible role `snmp_agent`
- Playbook: `ansible/playbooks/deploy-snmp-agents.yml`
- Monitors: vault-01, runner-01, postgres-01, authentik-01, akvorado-01, n8n-01, panda9000, lancache
- Metrics: CPU, memory, disk, load, network, process counts
- Community string: Vault at `secret/infrastructure/snmp`

*Network Devices:*
- mgmt-sw-01 (Catalyst 2960X): Interface stats, status, errors
- OPNsense firewall: 13 interfaces (igb0-3, VLANs 010/020/030/031, tailscale0, virtual)

*Configuration:*
- SNMP exporter: `snmp-exporter` namespace
- Prometheus scrape config: `prometheus-snmp-scrape-config` secret
- Target discovery: `/targets/snmp-targets.json` (generated by netbox-sync)
- Module: `if_mib` for interface monitoring

**Kubernetes Node Monitoring:**

*node-exporter DaemonSet:*
- Deployed to: `node-exporter` namespace
- Monitors: talos-cp-01, talos-bdg-qhb
- Metrics: CPU, memory, disk, network, system stats
- Manifest: `kubernetes/infrastructure/node-exporter/daemonset.yaml`
- Namespace: Privileged (required for host access)
- ServiceMonitor: Auto-discovered by Prometheus

**Grafana Dashboards:**

*Infrastructure Overview* (`lanmine-infra`):
- Device status bar gauge (all 12 devices)
- CPU usage - Kubernetes nodes
- Memory usage - Kubernetes nodes
- Disk usage - Kubernetes nodes
- Network traffic - Kubernetes nodes
- ConfigMap: `kubernetes/apps/monitoring/dashboards/infrastructure-overview.yaml`

*SNMP Monitored Devices* (`lanmine-snmp`):
- Total SNMP devices (stat panel)
- Devices up/down (stat panels)
- Devices by name (pie chart)
- Device status table with uptime
- Network interface traffic time series
- ConfigMap: `kubernetes/apps/monitoring/dashboards/snmp-devices.yaml`

**Prometheus Alerting:**

*Alert Rules* (16 total):
- PrometheusRule: `monitoring-alerts` in monitoring namespace
- Manifest: `kubernetes/apps/monitoring/monitoring-alerts.yaml`

*SNMP Devices (2 alerts):*
- SNMPDeviceDown: Device unreachable >5min (critical)
- SNMPDeviceHighUptime: Device uptime >365 days (info)

*Linux VMs (8 alerts):*
- LinuxVMDown: VM unreachable >5min (critical)
- LinuxVMHighCPUUsage: CPU >85% for 10min (warning)
- LinuxVMHighMemoryUsage: Memory >85% for 10min (warning)
- LinuxVMHighDiskUsage: Disk >85% for 10min (warning)
- LinuxVMCriticalDiskUsage: Disk >95% for 5min (critical)
- LinuxVMHighLoadAverage: Load >1.5× CPU count for 15min (warning)
- LinuxVMDiskWillFillIn24Hours: Predictive disk full (warning)
- LinuxVMOutOfInodes: <10% inodes available (warning)

*Network Interfaces (4 alerts):*
- NetworkInterfaceDown: Interface operationally down (warning)
- NetworkInterfaceHighTrafficIn: Inbound >80% capacity (warning)
- NetworkInterfaceHighTrafficOut: Outbound >80% capacity (warning)
- NetworkInterfaceErrors: >10 errors in 5min (warning)

*Email Notifications:*
- Receiver: tech@lanmine.no
- SMTP: smtp.domeneshop.no:587 with TLS
- Credentials: Vault at `secret/infrastructure/smtp`
- Group wait: 30s, Group interval: 5m, Repeat: 4h
- Subject format: `[FIRING/RESOLVED] {alertname}`
- Tested and verified working

**Uptime Kuma:**

*Availability Monitoring:*
- Deployment: uptime-kuma namespace
- Access: https://uptime.lionfish-caiman.ts.net
- Database: SQLite at `/app/data/kuma.db`
- Total monitors: 16 active

*HTTP Monitors (10):*
- OPNsense (10.0.10.1)
- Proxmox (10.0.10.5:8006)
- Vault (10.0.10.21:8200)
- Authentik (10.0.10.25:9443)
- Akvorado (10.0.10.26:8080)
- n8n (10.0.10.27:5678)
- Traefik (10.0.10.40:80)
- Grafana (10.0.10.40/grafana)
- PostgreSQL (10.0.10.23, ping)
- LANcache (10.0.20.2, ping)

*ICMP Ping Monitors (6):*
- GitHub Runner (10.0.10.22)
- Panda9000 (10.0.10.28)
- mgmt-sw-01 (10.0.99.101)
- Talos CP-01 (10.0.10.30)
- Talos Worker-01 (10.0.10.31)
- Talos Worker-02 (10.0.10.32)

*Configuration:*
- Check interval: 60s
- Retry interval: 60s
- All monitors active and reporting

**Monitoring Coverage:**

| Device | SNMP | node-exporter | Uptime Kuma | Status |
|--------|------|---------------|-------------|--------|
| OPNsense | ✓ | - | ✓ | 100% |
| Proxmox | - | - | ✓ | Available |
| vault-01 | ✓ | - | ✓ | 100% |
| runner-01 | ✓ | - | ✓ | 100% |
| postgres-01 | ✓ | - | ✓ | 100% |
| authentik-01 | ✓ | - | ✓ | 100% |
| akvorado-01 | ✓ | - | ✓ | 100% |
| n8n-01 | ✓ | - | ✓ | 100% |
| panda9000 | ✓ | - | ✓ | 100% |
| lancache | ✓ | - | ✓ | 100% |
| mgmt-sw-01 | ✓ | - | ✓ | 100% |
| talos-cp-01 | - | ✓ | ✓ | 100% |
| talos-bdg-qhb | - | ✓ | ✓ | 100% |
| **Total** | **9** | **2** | **13** | **100%** |

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

## Akvorado (Network Flow Collector)

Akvorado runs on a dedicated VM (`akvorado-01`, 10.0.10.26) outside the Kubernetes cluster, collecting NetFlow data from OPNsense.

**Architecture:**
- **Inlet**: Receives NetFlow/IPFIX/sFlow UDP packets, sends raw flows to Kafka
- **Outlet**: Decodes flows, enriches with metadata, writes to ClickHouse
- **Console**: Web UI for visualization
- **ClickHouse**: Time-series database for flow storage
- **Kafka + Zookeeper**: Message queue between inlet and outlet

**Flow Collection Ports:**
| Port | Protocol |
|------|----------|
| 2055/udp | NetFlow v5/v9 |
| 4739/udp | IPFIX |
| 6343/udp | sFlow |

**Configuration:**
- Ansible role: `ansible/roles/akvorado_install/`
- Docker Compose stack at `/opt/akvorado/` on the VM
- Interface mappings defined in `defaults/main.yml` (required for metadata enrichment)
- OPNsense exports NetFlow v9 to 10.0.10.26:2055

**Tailscale Access:** https://akvorado.lionfish-caiman.ts.net

## LANcache (Game Download Cache)

LANcache runs on a physical server (`ubuntu-mgmt02`, 10.0.20.2) on VLAN 20 with LAN contestants, caching game downloads from Steam, Origin, Epic, etc.

**Architecture:**
- **lancache-dns**: Intercepts CDN domain queries, returns LANcache IP
- **lancache-monolithic**: Caches HTTP game downloads, proxies HTTPS

**Ports:**
| Port | Protocol |
|------|----------|
| 53/udp | DNS (lancache-dns) |
| 80/tcp | HTTP cache |
| 443/tcp | HTTPS passthrough (SNI proxy) |

**Configuration:**
- Ansible role: `ansible/roles/lancache_install/`
- Docker Compose stack at `/opt/lancache/` on the server
- Cache storage at `/cache/`
- Vault secrets at `secret/infrastructure/lancache`

**Deployment:**
```bash
cd ansible && ansible-playbook playbooks/deploy-lancache.yml
```

## n8n (Workflow Automation)

n8n runs on a dedicated VM (`n8n-01`, 10.0.10.27) providing AI-powered workflow automation with Azure OpenAI integration.

**Architecture:**
- **n8n**: Workflow engine with queue mode
- **PostgreSQL**: Workflow and execution storage
- **Redis**: Job queue for worker scaling

**Ports:**
| Port | Protocol |
|------|----------|
| 5678/tcp | Web UI and API |

**Configuration:**
- Ansible role: `ansible/roles/n8n_install/`
- Docker Compose stack at `/opt/n8n/` on the VM
- Vault secrets at `secret/infrastructure/n8n`

**Code-First Workflow Management:**
- Workflows stored as JSON in `ansible/files/n8n-workflows/`
- Claude generates workflow JSON from natural language descriptions
- Deploy via: `ansible-playbook playbooks/deploy-n8n-workflows.yml`

**Deployment:**
```bash
# Deploy n8n service
cd ansible && ansible-playbook playbooks/deploy-n8n.yml

# Deploy workflows from JSON files
ansible-playbook playbooks/deploy-n8n-workflows.yml
```

**Tailscale Access:** https://n8n.lionfish-caiman.ts.net

## Network Architecture

**VLANs:**
| VLAN | Subnet | Purpose | Gateway |
|------|--------|---------|---------|
| LAN | 10.0.1.0/24 | Management LAN | 10.0.1.1 |
| 10 | 10.0.10.0/24 | Infrastructure | 10.0.10.1 |
| 20 | 10.0.20.0/23 | Contestants | 10.0.20.1 |
| 30 | 10.0.30.0/24 | OOB/iDRAC | 10.0.30.1 |

**Core Network (planned):**
- 2 × Nexus switches in vPC domain
- LANcache: 2 × 10G LACP bond (20 Gbps aggregate)
- HSRP for gateway redundancy
- Edge switches: 10G uplinks, 1G to clients

**LANcache Bonding (802.3ad LACP):**
```yaml
# /etc/netplan/01-lancache.yaml - bond config
bonds:
  bond0:
    interfaces: [eno49, eno50]
    parameters:
      mode: 802.3ad
      lacp-rate: fast
      transmit-hash-policy: layer3+4
```

## Switch Management (ZTP)

**VLAN 99 (10.0.99.0/24)** - Dedicated management network for switches, isolated from VLAN 10 (Infrastructure).

**ZTP Server:** ubuntu-mgmt01 (10.0.99.20)
- TFTP: UDP 69 → /srv/tftp/ (bootstrap configs)
- HTTP: TCP 80 → /srv/http/switches/ (IOS images)

**Switch Provisioning:**
1. Register switch in `ansible/inventory/switches.yml` (MAC, serial, model, role)
2. Generate ZTP configs: `cd ansible && ansible-playbook playbooks/generate-ztp-configs.yml`
3. Power on switch → ZTP (DHCP + TFTP) → bootstrap applied (~2 min)
4. Ansible deploys full config: `ansible-playbook playbooks/provision-new-switch.yml`
5. Post-provision tasks: `ansible-playbook playbooks/post-provision-switch.yml -e switch_hostname=<hostname>`
   - Registers switch in NetBox (device, interface, IP address)
   - Verifies switch appears in Ansible dynamic inventory
   - Confirms NetBox integration

**OPNsense DHCP (Kea):**
- Pool: 10.0.99.100-200
- Option 150: 10.0.99.20 (TFTP server)
- Static reservations by MAC

**Secrets:** `secret/infrastructure/switches/` in Vault

**Templates:**
- `ansible/templates/switches/ztp-bootstrap.j2` - Minimal ZTP config
- `ansible/templates/switches/core-nexus.j2` - Nexus 9100 cores
- `ansible/templates/switches/edge-ios.j2` - Catalyst edge switches

**Monitoring:**
- SNMP exporter in Kubernetes (metrics to Prometheus)
- Oxidized for config backups (Git repo)
- TACACS+ for centralized authentication (Authentik LDAP)
- NetBox for inventory (https://netbox.hl0.dev)

**Troubleshooting:**

Test switch SSH credentials:
```bash
cd ansible && ./scripts/test-switch-credentials.sh <switch-ip-or-hostname>
```

Password recovery (requires console access):
- See `docs/switch-password-recovery.md` for detailed procedures
- Common causes: ZTP bootstrap not applied, provision playbook not run
- Vault credentials: `vault kv get secret/infrastructure/switches/global`

## DHCP (Kea)

OPNsense runs Kea DHCP for all networks (dnsmasq disabled).

| Network | Pool | DNS | Description |
|---------|------|-----|-------------|
| LAN | 10.0.1.3-254 | 10.0.1.1 | Management |
| VLAN 10 | 10.0.10.100-110 | 10.0.10.1 | Infrastructure |
| VLAN 20 | 10.0.20.5-21.254 | 10.0.20.2 (LANcache) | Contestants |

- Kea API: `https://10.0.10.1/api/kea/dhcpv4/`

## MCP Servers

Claude Code has access to these MCP servers for this repository:

| Server | Purpose |
|--------|---------|
| `postgres` | Query Terraform state backend directly |
| `github-server` | GitHub API operations (issues, PRs, repos) |
| `vault` | HashiCorp Vault secret access |
| `proxmox` | Proxmox VE management (55 tools for VMs, containers, storage) |

MCP binaries:
- Vault: `~/vault-mcp-server/vault-mcp-server`
- Proxmox: `~/mcp-proxmox/index.js` (Node.js, from gilby125/mcp-proxmox)

## Code Style

- Terraform: snake_case for resources/variables, format with `terraform fmt`
- Shell scripts: Use `set -euo pipefail`, descriptive error messages
- File naming: kebab-case
- Never hardcode secrets; always use Vault

## Git Commits

- Do NOT add "Generated with Claude Code" or "Co-Authored-By: Claude" to commit messages
- Keep commit messages concise and descriptive
