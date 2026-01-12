---
layout: default
---

```

  ██╗      █████╗ ███╗   ██╗███╗   ███╗██╗███╗   ██╗███████╗
  ██║     ██╔══██╗████╗  ██║████╗ ████║██║████╗  ██║██╔════╝
  ██║     ███████║██╔██╗ ██║██╔████╔██║██║██╔██╗ ██║█████╗
  ██║     ██╔══██║██║╚██╗██║██║╚██╔╝██║██║██║╚██╗██║██╔══╝
  ███████╗██║  ██║██║ ╚████║██║ ╚═╝ ██║██║██║ ╚████║███████╗
  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝

  lanmine@infra
  -------------
  OS           Proxmox VE 8.x / Talos Linux v1.11.5
  Hypervisor   Dell PowerEdge R630 (proxmox01)
  Kernel       Kubernetes v1.34.1
  Uptime       35+ days

  VMs          9 running (11 total)
  K8s Nodes    3 (1 control-plane, 2 workers)
  Containers   50+

  Network      OPNsense 24.x
  VLANs        LAN, Infra (10), Contestants (20), OOB (30)
  DNS          Kea DHCP + LANcache DNS

  IaC          Terraform + Ansible
  GitOps       Flux CD v2.7.5
  Secrets      HashiCorp Vault

  Monitoring   Prometheus + Grafana + Loki
  Alerting     Alertmanager → n8n → Discord
  Uptime       Uptime Kuma (30s checks)

  Storage      Longhorn (distributed)
  Backup       age-encrypted → Git

  ████████████████████████████████████████
```

---

## Stack

| Layer | Technology |
|-------|------------|
| **Hypervisor** | Proxmox VE on Dell R630 |
| **Orchestration** | Talos Linux + Kubernetes |
| **Ingress** | Traefik + Tailscale |
| **Certificates** | cert-manager + internal CA |
| **Load Balancer** | MetalLB |
| **Storage** | Longhorn |
| **Monitoring** | kube-prometheus-stack |
| **Logs** | Loki + Promtail |
| **Identity** | Authentik SSO |
| **Automation** | n8n + Azure OpenAI |
| **Game Cache** | LANcache (2TB SSD) |
| **Flow Analysis** | Akvorado + ClickHouse |

---

## Services

| Service | Purpose |
|---------|---------|
| **Glance** | Dashboard |
| **Grafana** | Metrics visualization |
| **Alertmanager** | Alert routing |
| **Uptime Kuma** | Real-time monitoring |
| **n8n** | Workflow automation |
| **Vault** | Secrets management |
| **Authentik** | SSO & Identity |
| **LANcache** | Game download cache |
| **Akvorado** | Network flow collector |

---

## Network

```
┌─────────────────────────────────────────────────────────┐
│                      OPNsense                           │
│                     (Gateway)                           │
└──────────┬──────────┬──────────┬──────────┬────────────┘
           │          │          │          │
     ┌─────┴─────┐ ┌──┴──┐ ┌─────┴─────┐ ┌──┴──┐
     │   LAN     │ │ V10 │ │    V20    │ │ V30 │
     │ 10.0.1.0  │ │Infra│ │Contestants│ │ OOB │
     └───────────┘ └─────┘ └───────────┘ └─────┘
                      │          │
                ┌─────┴─────┐    │
                │  Proxmox  │    │
                │   + K8s   │    │
                └───────────┘    │
                           ┌─────┴─────┐
                           │ LANcache  │
                           │  (R630)   │
                           └───────────┘
```

---

<sub>Infrastructure as Code: [github.com/Lanmine/lanmine_tech](https://github.com/Lanmine/lanmine_tech)</sub>
