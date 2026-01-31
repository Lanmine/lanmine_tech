---
layout: default
---

```
 _                      _
| | __ _ _ __  _ __ ___ (_)_ __   ___
| |/ _` | '_ \| '_ ` _ \| | '_ \ / _ \
| | (_| | | | | | | | | | | | | |  __/
|_|\__,_|_| |_|_| |_| |_|_|_| |_|\___|

lanmine@infra
-------------
OS        Proxmox VE 8 / Talos v1.11
Host      Dell PowerEdge R630
Kernel    Kubernetes v1.34.1

VMs       9 running
K8s       3 nodes (1 CP, 2 workers)

Network   OPNsense 24.x
VLANs     Infra, Contestants, OOB

IaC       Terraform + Ansible
GitOps    ArgoCD v3.2
Secrets   HashiCorp Vault

Monitor   Prometheus + Grafana
Alerts    n8n → Discord
```

---

## Recent Updates

{% for post in site.posts limit:5 %}
### [{{ post.title }}]({{ post.url | relative_url }})
<small>{{ post.date | date: "%B %d, %Y" }}</small>

{{ post.excerpt | strip_html | truncatewords: 50 }}

---
{% endfor %}

{% if site.posts.size == 0 %}
*No posts yet. Daily updates coming soon.*
{% endif %}

[View all posts](/lanmine_tech/blog/)
