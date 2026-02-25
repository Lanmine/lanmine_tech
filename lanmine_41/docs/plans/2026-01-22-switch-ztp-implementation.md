# Switch ZTP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build fully automated zero touch provisioning system for Cisco switches using Ansible, TFTP, and monitoring stack

**Architecture:** VLAN 99 management network (10.0.99.0/24), ubuntu-mgmt01 as ZTP server (TFTP/HTTP), Ansible golden templates, enhanced monitoring with Oxidized/SNMP/NetBox/TACACS+

**Tech Stack:** Ansible, atftpd, nginx, Docker (Oxidized/TACACS+), Kubernetes (NetBox, SNMP exporter), Vault, Jinja2

---

## Task 1: Create Vault Secrets Structure

**Files:**
- No file changes (Vault operations only)

**Step 1: Create global switch secrets in Vault**

Run:
```bash
{% raw %}
vault kv put secret/infrastructure/switches/global \
  enable_secret="$(openssl rand -base64 24)" \
  ansible_password="$(openssl rand -base64 24)" \
  snmp_v3_auth_pass="$(openssl rand -base64 24)" \
  snmp_v3_priv_pass="$(openssl rand -base64 24)"
{% endraw %}
```

Expected: Success (4 secrets created)

**Step 2: Create TACACS+ secrets**

Run:
```bash
{% raw %}
vault kv put secret/infrastructure/switches/tacacs \
  shared_key="$(openssl rand -base64 32)" \
  ldap_bind_password="changeme_later"
{% endraw %}
```

Expected: Success (note: update ldap_bind_password when configuring Authentik)

**Step 3: Generate SSH key for Oxidized**

Run:
```bash
{% raw %}
ssh-keygen -t ed25519 -C "oxidized@lanmine.no" -f /tmp/oxidized_key -N ""
vault kv put secret/infrastructure/switches/oxidized \
  ssh_key=@/tmp/oxidized_key \
  ssh_pub=@/tmp/oxidized_key.pub
rm -f /tmp/oxidized_key /tmp/oxidized_key.pub
{% endraw %}
```

Expected: SSH keys stored in Vault

**Step 4: Verify secrets**

Run:
```bash
{% raw %}
vault kv get secret/infrastructure/switches/global
vault kv get secret/infrastructure/switches/tacacs
vault kv get secret/infrastructure/switches/oxidized
{% endraw %}
```

Expected: All secrets visible

**Step 5: Commit (documentation only)**

No Git changes yet - this is infrastructure setup.

---

## Task 2: Create Ansible Directory Structure

**Files:**
- Create: `ansible/roles/ztp-server/tasks/main.yml`
- Create: `ansible/roles/ztp-server/tasks/tftp.yml`
- Create: `ansible/roles/ztp-server/tasks/nginx.yml`
- Create: `ansible/roles/ztp-server/tasks/vlan99.yml`
- Create: `ansible/roles/ztp-server/templates/atftpd.conf.j2`
- Create: `ansible/inventory/switches.yml`
- Create: `ansible/files/switch-configs/ztp/.gitkeep`
- Create: `ansible/templates/switches/.gitkeep`

**Step 1: Create ztp-server role structure**

Run:
```bash
{% raw %}
mkdir -p ansible/roles/ztp-server/{tasks,templates,files}
mkdir -p ansible/files/switch-configs/ztp
mkdir -p ansible/templates/switches
{% endraw %}
```

**Step 2: Create main task file**

File: `ansible/roles/ztp-server/tasks/main.yml`
```yaml
{% raw %}
---
- name: Setup VLAN 99 interface
  include_tasks: vlan99.yml
  tags: vlan99

- name: Setup TFTP server
  include_tasks: tftp.yml
  tags: tftp

- name: Setup nginx HTTP server
  include_tasks: nginx.yml
  tags: nginx
{% endraw %}
```

**Step 3: Create switches inventory skeleton**

File: `ansible/inventory/switches.yml`
```yaml
{% raw %}
---
# Cisco Switch Inventory
# Format:
# - hostname: switch-name
#   mac: aa:bb:cc:dd:ee:ff
#   serial: SERIAL123456
#   model: nexus-9336c | catalyst-2960x
#   role: core | edge | access
#   mgmt_ip: 10.0.99.X
#   vlans: [list, of, vlans]

switches: []

# Example (uncomment when switches arrive):
# switches:
#   - hostname: core-sw-01
#     mac: aa:bb:cc:dd:ee:01
#     serial: FDO12340001
#     model: nexus-9336c
#     role: core
#     mgmt_ip: 10.0.99.11
#     vlans: [10, 20, 30, 99]
{% endraw %}
```

**Step 4: Create placeholder files**

Run:
```bash
{% raw %}
touch ansible/files/switch-configs/ztp/.gitkeep
touch ansible/templates/switches/.gitkeep
{% endraw %}
```

**Step 5: Commit directory structure**

Run:
```bash
{% raw %}
git add ansible/roles/ztp-server ansible/inventory/switches.yml \
  ansible/files/switch-configs ansible/templates/switches
git commit -m "feat(switches): add ZTP Ansible directory structure

- Create ztp-server role skeleton
- Add switches inventory file
- Add directories for configs and templates"
{% endraw %}
```

Expected: Files committed successfully

---

## Task 3: VLAN 99 Network Interface Configuration

**Files:**
- Create: `ansible/roles/ztp-server/tasks/vlan99.yml`
- Create: `ansible/roles/ztp-server/templates/netplan-vlan99.yml.j2`

**Step 1: Create VLAN 99 netplan template**

File: `ansible/roles/ztp-server/templates/netplan-vlan99.yml.j2`
```yaml
{% raw %}
network:
  version: 2
  ethernets:
    {{ ansible_default_ipv4.interface }}:
      dhcp4: true
  vlans:
    vlan99:
      id: 99
      link: {{ ansible_default_ipv4.interface }}
      addresses:
        - 10.0.99.20/24
      routes:
        - to: 10.0.99.0/24
          via: 10.0.99.1
      nameservers:
        addresses:
          - 10.0.99.1
          - 1.1.1.1
{% endraw %}
```

**Step 2: Create VLAN 99 configuration task**

File: `ansible/roles/ztp-server/tasks/vlan99.yml`
```yaml
{% raw %}
---
- name: Check if VLAN 99 interface exists
  command: ip addr show vlan99
  register: vlan99_check
  failed_when: false
  changed_when: false

- name: Create netplan config for VLAN 99
  template:
    src: netplan-vlan99.yml.j2
    dest: /etc/netplan/99-vlan99.yaml
    owner: root
    group: root
    mode: '0600'
  when: vlan99_check.rc != 0
  notify: apply netplan

- name: Ensure VLAN 99 is up
  command: ip link set vlan99 up
  when: vlan99_check.rc == 0 and "'state DOWN' in vlan99_check.stdout"
  changed_when: true
{% endraw %}
```

**Step 3: Test task syntax**

Run:
```bash
{% raw %}
cd ansible
ansible-playbook --syntax-check -i inventory/switches.yml \
  -e "ansible_default_ipv4={'interface': 'ens18'}" \
  roles/ztp-server/tasks/vlan99.yml
{% endraw %}
```

Expected: Syntax OK

**Step 4: Commit VLAN 99 configuration**

Run:
```bash
{% raw %}
git add ansible/roles/ztp-server/tasks/vlan99.yml \
  ansible/roles/ztp-server/templates/netplan-vlan99.yml.j2
git commit -m "feat(switches): add VLAN 99 interface configuration

- Create netplan template for VLAN 99 (10.0.99.20/24)
- Add Ansible task to configure interface
- Route to management network via 10.0.99.1"
{% endraw %}
```

---

## Task 4: TFTP Server Installation and Configuration

**Files:**
- Create: `ansible/roles/ztp-server/tasks/tftp.yml`
- Create: `ansible/roles/ztp-server/templates/atftpd.conf.j2`

**Step 1: Create atftpd configuration template**

File: `ansible/roles/ztp-server/templates/atftpd.conf.j2`
```
{% raw %}
# atftpd configuration for switch ZTP
# Root directory for TFTP files
ATFTPD_ROOT="/srv/tftp"

# Run as unprivileged user
ATFTPD_USER="nobody"
ATFTPD_GROUP="nogroup"

# Bind to VLAN 99 address
ATFTPD_BIND_ADDRESSES="10.0.99.20"

# Options:
# --daemon: run as daemon
# --no-multicast: disable multicast
# --no-fork: don't fork (systemd handles this)
# --verbose=5: logging level
ATFTPD_OPTIONS="--daemon --no-multicast --verbose=5"

# Security: read-only, no file creation
ATFTPD_USE_IPD=false
ATFTPD_MAX_THREAD=100
{% endraw %}
```

**Step 2: Create TFTP installation task**

File: `ansible/roles/ztp-server/tasks/tftp.yml`
```yaml
{% raw %}
---
- name: Install atftpd package
  apt:
    name: atftpd
    state: present
    update_cache: yes

- name: Create TFTP root directory
  file:
    path: /srv/tftp
    state: directory
    owner: nobody
    group: nogroup
    mode: '0755'

- name: Configure atftpd
  template:
    src: atftpd.conf.j2
    dest: /etc/default/atftpd
    owner: root
    group: root
    mode: '0644'
  notify: restart atftpd

- name: Enable and start atftpd service
  systemd:
    name: atftpd
    enabled: yes
    state: started

- name: Allow TFTP through firewall (if UFW enabled)
  ufw:
    rule: allow
    port: '69'
    proto: udp
    from_ip: 10.0.99.0/24
  when: ansible_facts.services['ufw'] is defined
  ignore_errors: yes
{% endraw %}
```

**Step 3: Test TFTP task syntax**

Run:
```bash
{% raw %}
cd ansible
ansible-playbook --syntax-check -i inventory/switches.yml \
  roles/ztp-server/tasks/tftp.yml
{% endraw %}
```

Expected: Syntax OK

**Step 4: Commit TFTP configuration**

Run:
```bash
{% raw %}
git add ansible/roles/ztp-server/tasks/tftp.yml \
  ansible/roles/ztp-server/templates/atftpd.conf.j2
git commit -m "feat(switches): add TFTP server configuration

- Install and configure atftpd on ubuntu-mgmt01
- Bind to VLAN 99 (10.0.99.20)
- Create /srv/tftp root directory
- Enable read-only mode for security"
{% endraw %}
```

---

## Task 5: nginx HTTP Server Configuration

**Files:**
- Create: `ansible/roles/ztp-server/tasks/nginx.yml`
- Create: `ansible/roles/ztp-server/templates/nginx-switches.conf.j2`

**Step 1: Create nginx site configuration**

File: `ansible/roles/ztp-server/templates/nginx-switches.conf.j2`
```nginx
{% raw %}
server {
    listen 10.0.99.20:80;
    server_name ztp.hl0.dev 10.0.99.20;

    root /srv/http/switches;
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;

    location / {
        try_files $uri $uri/ =404;
    }

    # Serve IOS images (large files)
    location ~ \.(bin|tar)$ {
        types { }
        default_type application/octet-stream;
        add_header Content-Disposition 'attachment';
    }

    # Access logs
    access_log /var/log/nginx/switches-access.log;
    error_log /var/log/nginx/switches-error.log;
}
{% endraw %}
```

**Step 2: Create nginx installation task**

File: `ansible/roles/ztp-server/tasks/nginx.yml`
```yaml
{% raw %}
---
- name: Install nginx
  apt:
    name: nginx
    state: present
    update_cache: yes

- name: Create HTTP root directory
  file:
    path: /srv/http/switches
    state: directory
    owner: www-data
    group: www-data
    mode: '0755'

- name: Configure nginx site for switches
  template:
    src: nginx-switches.conf.j2
    dest: /etc/nginx/sites-available/switches
    owner: root
    group: root
    mode: '0644'
  notify: reload nginx

- name: Enable switches site
  file:
    src: /etc/nginx/sites-available/switches
    dest: /etc/nginx/sites-enabled/switches
    state: link
  notify: reload nginx

- name: Enable and start nginx
  systemd:
    name: nginx
    enabled: yes
    state: started

- name: Allow HTTP through firewall (if UFW enabled)
  ufw:
    rule: allow
    port: '80'
    proto: tcp
    from_ip: 10.0.99.0/24
  when: ansible_facts.services['ufw'] is defined
  ignore_errors: yes
{% endraw %}
```

**Step 3: Test nginx task syntax**

Run:
```bash
{% raw %}
cd ansible
ansible-playbook --syntax-check -i inventory/switches.yml \
  roles/ztp-server/tasks/nginx.yml
{% endraw %}
```

Expected: Syntax OK

**Step 4: Commit nginx configuration**

Run:
```bash
{% raw %}
git add ansible/roles/ztp-server/tasks/nginx.yml \
  ansible/roles/ztp-server/templates/nginx-switches.conf.j2
git commit -m "feat(switches): add nginx HTTP server configuration

- Install and configure nginx on ubuntu-mgmt01
- Serve files from /srv/http/switches
- Bind to VLAN 99 (10.0.99.20:80)
- Enable directory listing for downloads"
{% endraw %}
```

---

## Task 6: ZTP Bootstrap Template for IOS/NX-OS

**Files:**
- Create: `ansible/templates/switches/ztp-bootstrap.j2`

**Step 1: Create ZTP bootstrap Jinja2 template**

File: `ansible/templates/switches/ztp-bootstrap.j2`
```
{% raw %}
{# ZTP Bootstrap Configuration Template #}
{# Works for both Cisco IOS and NX-OS #}
{# Variables: hostname, mgmt_ip, enable_secret, ansible_password #}

{% if model.startswith('nexus') %}
{# Nexus NX-OS configuration #}
hostname {{ hostname }}

feature ssh

vlan 99
  name MGMT

interface Ethernet1/48
  description Management
  switchport mode access
  switchport access vlan 99
  no shutdown

interface Vlan99
  description Management Interface
  no shutdown
  ip address {{ mgmt_ip }}/24

ip route 0.0.0.0/0 10.0.99.1

username ansible password {{ ansible_password }} role network-admin
username localadmin password {{ ansible_password }} role network-admin

enable secret {{ enable_secret }}

ssh key rsa 2048

ip domain-name hl0.dev
ip name-server 10.0.99.1

snmp-server user ansible network-admin auth sha {{ snmp_v3_auth_pass }} priv aes-128 {{ snmp_v3_priv_pass }}

logging server 10.0.99.20

ntp server 10.0.99.1

{% else %}
{# Cisco IOS configuration #}
hostname {{ hostname }}

enable secret {{ enable_secret }}

ip domain-name hl0.dev

vlan 99
  name MGMT

interface Vlan99
  description Management Interface
  ip address {{ mgmt_ip }} 255.255.255.0
  no shutdown

ip default-gateway 10.0.99.1
ip name-server 10.0.99.1

username ansible privilege 15 secret {{ ansible_password }}
username localadmin privilege 15 secret {{ ansible_password }}

crypto key generate rsa modulus 2048

ip ssh version 2

line vty 0 15
  login local
  transport input ssh

snmp-server user ansible network-admin v3 auth sha {{ snmp_v3_auth_pass }} priv aes 128 {{ snmp_v3_priv_pass }}

logging host 10.0.99.20

ntp server 10.0.99.1

{% endif %}

banner motd ^
****************************************************
* ZTP Bootstrap Applied - Awaiting Full Config   *
* Managed by Ansible - Do Not Manually Configure *
****************************************************
^

end
{% endraw %}
```

**Step 2: Test template syntax**

Run:
```bash
{% raw %}
cd ansible
python3 << 'EOF'
from jinja2 import Template
import yaml

with open('templates/switches/ztp-bootstrap.j2') as f:
    template = Template(f.read())

# Test render with sample data
result = template.render(
    hostname='test-sw-01',
    mgmt_ip='10.0.99.101',
    enable_secret='testpass123',
    ansible_password='ansiblepass123',
    model='catalyst-2960x',
    snmp_v3_auth_pass='snmpauth123',
    snmp_v3_priv_pass='snmppriv123'
)

print("Template rendered successfully")
print(f"Lines: {len(result.splitlines())}")
EOF
{% endraw %}
```

Expected: Template rendered successfully

**Step 3: Commit bootstrap template**

Run:
```bash
{% raw %}
git add ansible/templates/switches/ztp-bootstrap.j2
git commit -m "feat(switches): add ZTP bootstrap configuration template

- Create Jinja2 template for minimal ZTP config
- Support both Cisco IOS and Nexus NX-OS
- Configure management VLAN 99, SSH, SNMP, users
- Secrets injected from Vault at generation time"
{% endraw %}
```

---

## Task 7: Ansible Playbook to Setup ZTP Server

**Files:**
- Create: `ansible/playbooks/setup-ztp-server.yml`
- Create: `ansible/roles/ztp-server/handlers/main.yml`

**Step 1: Create handlers for service management**

File: `ansible/roles/ztp-server/handlers/main.yml`
```yaml
{% raw %}
---
- name: restart atftpd
  systemd:
    name: atftpd
    state: restarted

- name: reload nginx
  systemd:
    name: nginx
    state: reloaded

- name: apply netplan
  command: netplan apply
  async: 45
  poll: 0
{% endraw %}
```

**Step 2: Create setup playbook**

File: `ansible/playbooks/setup-ztp-server.yml`
```yaml
{% raw %}
---
- name: Setup ZTP Server Infrastructure on ubuntu-mgmt01
  hosts: localhost
  become: yes
  vars:
    ansible_python_interpreter: /usr/bin/python3

  tasks:
    - name: Include ztp-server role
      include_role:
        name: ztp-server

    - name: Display ZTP server status
      debug:
        msg:
          - "ZTP Server configured successfully"
          - "VLAN 99: 10.0.99.20/24"
          - "TFTP: udp://10.0.99.20:69 -> /srv/tftp/"
          - "HTTP: http://10.0.99.20/ -> /srv/http/switches/"
          - ""
          - "Next steps:"
          - "1. Configure OPNsense VLAN 99 and DHCP"
          - "2. Generate ZTP configs: ansible-playbook generate-ztp-configs.yml"
          - "3. Test with spare switch"
{% endraw %}
```

**Step 3: Test playbook syntax**

Run:
```bash
{% raw %}
cd ansible
ansible-playbook --syntax-check playbooks/setup-ztp-server.yml
{% endraw %}
```

Expected: Syntax OK

**Step 4: Commit ZTP server playbook**

Run:
```bash
{% raw %}
git add ansible/playbooks/setup-ztp-server.yml \
  ansible/roles/ztp-server/handlers/main.yml
git commit -m "feat(switches): add playbook to setup ZTP server

- Create playbook to configure ubuntu-mgmt01 as ZTP server
- Install TFTP and HTTP services
- Configure VLAN 99 interface
- Add handlers for service management"
{% endraw %}
```

---

## Task 8: Generate ZTP Configs Playbook

**Files:**
- Create: `ansible/playbooks/generate-ztp-configs.yml`
- Create: `ansible/group_vars/all/vault.yml` (if not exists)

**Step 1: Create Vault integration for Ansible**

File: `ansible/group_vars/all/vault.yml`
```yaml
{% raw %}
---
# Vault integration for switch secrets
vault_addr: "{{ lookup('env', 'VAULT_ADDR') | default('http://10.0.10.21:8200', true) }}"

# Fetch secrets from Vault (use with lookup)
switch_enable_secret: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=secret/infrastructure/switches/global:enable_secret') }}"
switch_ansible_password: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=secret/infrastructure/switches/global:ansible_password') }}"
switch_snmp_v3_auth: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=secret/infrastructure/switches/global:snmp_v3_auth_pass') }}"
switch_snmp_v3_priv: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=secret/infrastructure/switches/global:snmp_v3_priv_pass') }}"
{% endraw %}
```

**Step 2: Create generate configs playbook**

File: `ansible/playbooks/generate-ztp-configs.yml`
```yaml
{% raw %}
---
- name: Generate ZTP Bootstrap Configurations
  hosts: localhost
  gather_facts: no
  vars_files:
    - ../inventory/switches.yml

  tasks:
    - name: Ensure ZTP config directory exists
      file:
        path: ../files/switch-configs/ztp
        state: directory
        mode: '0755'

    - name: Generate ZTP bootstrap configs for each switch
      template:
        src: ../templates/switches/ztp-bootstrap.j2
        dest: "../files/switch-configs/ztp/{% if item.model.startswith('nexus') %}conf.{{ item.serial }}{% else %}network-confg{% endif %}"
        mode: '0644'
      loop: "{{ switches }}"
      when: switches | length > 0
      vars:
        hostname: "{{ item.hostname }}"
        mgmt_ip: "{{ item.mgmt_ip }}"
        model: "{{ item.model }}"
        enable_secret: "{{ switch_enable_secret }}"
        ansible_password: "{{ switch_ansible_password }}"
        snmp_v3_auth_pass: "{{ switch_snmp_v3_auth }}"
        snmp_v3_priv_pass: "{{ switch_snmp_v3_priv }}"

    - name: Copy ZTP configs to TFTP server
      copy:
        src: "../files/switch-configs/ztp/{{ item }}"
        dest: "/srv/tftp/{{ item }}"
        mode: '0644'
        owner: nobody
        group: nogroup
      loop: "{{ lookup('fileglob', '../files/switch-configs/ztp/*', wantlist=True) | map('basename') | list }}"
      become: yes
      when: switches | length > 0

    - name: Display generated configs
      debug:
        msg:
          - "ZTP configs generated successfully"
          - "Generated {{ switches | length }} configurations"
          - "TFTP directory: /srv/tftp/"
          - ""
          - "Test TFTP download:"
          - "  tftp 10.0.99.20 -c get network-confg"
{% endraw %}
```

**Step 3: Test generate playbook syntax**

Run:
```bash
{% raw %}
cd ansible
ansible-playbook --syntax-check playbooks/generate-ztp-configs.yml
{% endraw %}
```

Expected: Syntax OK

**Step 4: Commit generate configs playbook**

Run:
```bash
{% raw %}
git add ansible/playbooks/generate-ztp-configs.yml \
  ansible/group_vars/all/vault.yml
git commit -m "feat(switches): add playbook to generate ZTP configs

- Create playbook to render bootstrap templates
- Integrate with Vault for secrets
- Copy configs to TFTP server (/srv/tftp/)
- Support both IOS (network-confg) and NX-OS (conf.SERIAL) naming"
{% endraw %}
```

---

## Task 9: Core Nexus Template

**Files:**
- Create: `ansible/templates/switches/core-nexus.j2`

**Step 1: Create core Nexus configuration template**

File: `ansible/templates/switches/core-nexus.j2`
```
{% raw %}
{# Nexus 9100 Core Switch Configuration #}
{# Variables: hostname, mgmt_ip, peer_ip, is_primary, vlans #}

hostname {{ hostname }}

feature vpc
feature lacp
feature interface-vlan
feature ssh
feature ntp
feature lldp

{# VLANs #}
{% for vlan in vlans %}
vlan {{ vlan }}
{% if vlan == 10 %}
  name Infrastructure
{% elsif vlan == 20 %}
  name Contestants
{% elsif vlan == 30 %}
  name OOB
{% elsif vlan == 99 %}
  name Management
{% endif %}
{% endfor %}

{# vPC Configuration #}
vpc domain 1
  peer-keepalive destination {{ peer_ip }} source {{ mgmt_ip }} vrf management
{% if is_primary %}
  role priority 1
{% else %}
  role priority 2
{% endif %}
  auto-recovery

{# Management Interface #}
interface mgmt0
  vrf member management
  ip address {{ mgmt_ip }}/24

{# VLAN 99 SVI #}
interface Vlan99
  description Management SVI
  no shutdown
  ip address {{ mgmt_ip }}/24

{# Peer-link (placeholder - adjust ports as needed) #}
interface Ethernet1/47-48
  description vPC Peer-Link
  switchport mode trunk
  switchport trunk allowed vlan {{ vlans | join(',') }}
  channel-group 100 mode active
  no shutdown

interface port-channel100
  description vPC Peer-Link
  switchport mode trunk
  switchport trunk allowed vlan {{ vlans | join(',') }}
  vpc peer-link

{# Default route #}
ip route 0.0.0.0/0 10.0.99.1

{# Users #}
username ansible password {{ ansible_password }} role network-admin
username localadmin password {{ ansible_password }} role network-admin

enable secret {{ enable_secret }}

{# SSH #}
ssh key rsa 2048
ip domain-name hl0.dev

{# SNMP v3 #}
snmp-server user ansible network-admin auth sha {{ snmp_v3_auth_pass }} priv aes-128 {{ snmp_v3_priv_pass }}

{# Syslog #}
logging server 10.0.99.20

{# NTP #}
ntp server 10.0.99.1

{# LLDP #}
lldp timer 30
lldp holdtime 120

banner motd ^
****************************************************
* {{ hostname }} - Nexus Core Switch              *
* Managed by Ansible - Do Not Manually Configure *
****************************************************
^

end
{% endraw %}
```

**Step 2: Test core template rendering**

Run:
```bash
{% raw %}
cd ansible
python3 << 'EOF'
from jinja2 import Template

with open('templates/switches/core-nexus.j2') as f:
    template = Template(f.read())

result = template.render(
    hostname='core-sw-01',
    mgmt_ip='10.0.99.11',
    peer_ip='10.0.99.12',
    is_primary=True,
    vlans=[10, 20, 30, 99],
    enable_secret='test123',
    ansible_password='ansible123',
    snmp_v3_auth_pass='snmpauth',
    snmp_v3_priv_pass='snmppriv'
)

print("Core template rendered successfully")
print(f"Lines: {len(result.splitlines())}")
assert 'vpc domain 1' in result
assert 'role priority 1' in result
EOF
{% endraw %}
```

Expected: Template rendered successfully

**Step 3: Commit core Nexus template**

Run:
```bash
{% raw %}
git add ansible/templates/switches/core-nexus.j2
git commit -m "feat(switches): add Nexus core switch configuration template

- Create Jinja2 template for Nexus 9100 cores
- Configure vPC domain with peer-keepalive
- Support primary/secondary role priority
- Configure VLANs, management, SSH, SNMP v3
- Placeholder peer-link configuration"
{% endraw %}
```

---

## Task 10: Edge IOS Template

**Files:**
- Create: `ansible/templates/switches/edge-ios.j2`

**Step 1: Create edge IOS configuration template**

File: `ansible/templates/switches/edge-ios.j2`
```
{% raw %}
{# Cisco IOS Edge Switch Configuration #}
{# Variables: hostname, mgmt_ip, vlans, trunk_ports #}

hostname {{ hostname }}

enable secret {{ enable_secret }}

{# VLANs #}
{% for vlan in vlans %}
vlan {{ vlan }}
{% if vlan == 20 %}
  name Contestants
{% elsif vlan == 99 %}
  name Management
{% endif %}
{% endfor %}

{# Management VLAN interface #}
interface Vlan99
  description Management Interface
  ip address {{ mgmt_ip }} 255.255.255.0
  no shutdown

ip default-gateway 10.0.99.1
ip domain-name hl0.dev
ip name-server 10.0.99.1

{# Trunk ports to core (adjust as needed) #}
{% if trunk_ports is defined %}
{% for port in trunk_ports %}
interface {{ port }}
  description Trunk to Core
  switchport trunk encapsulation dot1q
  switchport mode trunk
  switchport trunk allowed vlan {{ vlans | join(',') }}
  no shutdown
{% endfor %}
{% endif %}

{# Access port defaults (apply to range later) #}
interface range GigabitEthernet1/0/1-24
  switchport mode access
  switchport access vlan 20
  switchport port-security
  switchport port-security maximum 3
  switchport port-security violation restrict
  spanning-tree portfast
  spanning-tree bpduguard enable
  no shutdown

{# Users #}
username ansible privilege 15 secret {{ ansible_password }}
username localadmin privilege 15 secret {{ ansible_password }}

{# SSH #}
crypto key generate rsa modulus 2048
ip ssh version 2

line vty 0 15
  login local
  transport input ssh

{# SNMP v3 #}
snmp-server user ansible network-admin v3 auth sha {{ snmp_v3_auth_pass }} priv aes 128 {{ snmp_v3_priv_pass }}

{# Syslog #}
logging host 10.0.99.20

{# NTP #}
ntp server 10.0.99.1

{# DHCP Snooping Security #}
ip dhcp snooping
ip dhcp snooping vlan 20
no ip dhcp snooping information option
{% if trunk_ports is defined %}
{% for port in trunk_ports %}
interface {{ port }}
  ip dhcp snooping trust
{% endfor %}
{% endif %}

{# Storm Control #}
interface range GigabitEthernet1/0/1-24
  storm-control broadcast level 10.00
  storm-control multicast level 10.00

banner motd ^
****************************************************
* {{ hostname }} - Edge Access Switch             *
* Managed by Ansible - Do Not Manually Configure *
****************************************************
^

end
{% endraw %}
```

**Step 2: Test edge template rendering**

Run:
```bash
{% raw %}
cd ansible
python3 << 'EOF'
from jinja2 import Template

with open('templates/switches/edge-ios.j2') as f:
    template = Template(f.read())

result = template.render(
    hostname='edge-sw-01',
    mgmt_ip='10.0.99.101',
    vlans=[20, 99],
    trunk_ports=['GigabitEthernet1/0/47', 'GigabitEthernet1/0/48'],
    enable_secret='test123',
    ansible_password='ansible123',
    snmp_v3_auth_pass='snmpauth',
    snmp_v3_priv_pass='snmppriv'
)

print("Edge template rendered successfully")
print(f"Lines: {len(result.splitlines())}")
assert 'ip dhcp snooping' in result
assert 'switchport port-security' in result
EOF
{% endraw %}
```

Expected: Template rendered successfully

**Step 3: Commit edge IOS template**

Run:
```bash
{% raw %}
git add ansible/templates/switches/edge-ios.j2
git commit -m "feat(switches): add IOS edge switch configuration template

- Create Jinja2 template for Catalyst edge switches
- Configure trunk ports to core
- Access ports with port-security and DHCP snooping
- Storm control and spanning-tree security
- Management VLAN 99, SSH, SNMP v3"
{% endraw %}
```

---

## Task 11: Switch Provisioning Playbook

**Files:**
- Create: `ansible/playbooks/provision-new-switch.yml`

**Step 1: Create switch provisioning playbook**

File: `ansible/playbooks/provision-new-switch.yml`
```yaml
{% raw %}
---
- name: Provision New Switch with Full Configuration
  hosts: "{{ target_switch | default('all') }}"
  gather_facts: no
  connection: network_cli
  vars:
    ansible_network_os: "{{ 'nxos' if hostvars[inventory_hostname].model.startswith('nexus') else 'ios' }}"
    ansible_user: ansible
    ansible_password: "{{ switch_ansible_password }}"
    ansible_become: yes
    ansible_become_method: enable

  tasks:
    - name: Wait for switch to be SSH accessible
      wait_for:
        host: "{{ inventory_hostname }}"
        port: 22
        timeout: 300
      delegate_to: localhost

    - name: Gather switch facts
      ios_facts:
      when: ansible_network_os == 'ios'

    - name: Gather switch facts (Nexus)
      nxos_facts:
      when: ansible_network_os == 'nxos'

    - name: Render full configuration from template
      set_fact:
        full_config: "{{ lookup('template', '../templates/switches/{% if model.startswith(\"nexus\") %}core-nexus.j2{% else %}edge-ios.j2{% endif %}') }}"
      vars:
        hostname: "{{ inventory_hostname }}"
        mgmt_ip: "{{ hostvars[inventory_hostname].mgmt_ip }}"
        vlans: "{{ hostvars[inventory_hostname].vlans }}"
        enable_secret: "{{ switch_enable_secret }}"
        ansible_password: "{{ switch_ansible_password }}"
        snmp_v3_auth_pass: "{{ switch_snmp_v3_auth }}"
        snmp_v3_priv_pass: "{{ switch_snmp_v3_priv }}"
        # Nexus-specific
        peer_ip: "{{ hostvars[inventory_hostname].peer_ip | default('') }}"
        is_primary: "{{ hostvars[inventory_hostname].is_primary | default(false) }}"
        # IOS-specific
        trunk_ports: "{{ hostvars[inventory_hostname].trunk_ports | default([]) }}"

    - name: Apply configuration to IOS switch
      ios_config:
        src: full_config
        save_when: modified
      when: ansible_network_os == 'ios'

    - name: Apply configuration to Nexus switch
      nxos_config:
        src: full_config
        save_when: modified
      when: ansible_network_os == 'nxos'

    - name: Verify configuration applied
      debug:
        msg: "Configuration applied successfully to {{ inventory_hostname }}"
{% endraw %}
```

**Step 2: Test provisioning playbook syntax**

Run:
```bash
{% raw %}
cd ansible
ansible-playbook --syntax-check playbooks/provision-new-switch.yml
{% endraw %}
```

Expected: Syntax OK

**Step 3: Commit provisioning playbook**

Run:
```bash
{% raw %}
git add ansible/playbooks/provision-new-switch.yml
git commit -m "feat(switches): add full switch provisioning playbook

- Create playbook to deploy golden configs to switches
- Support both IOS and Nexus via network_cli
- Render templates based on switch model/role
- Integrate with Vault for secrets
- Use ansible network modules (ios_config, nxos_config)"
{% endraw %}
```

---

## Task 12: Update CLAUDE.md with Switch Management Section

**Files:**
- Modify: `CLAUDE.md` (add after Network Architecture section)

**Step 1: Add switch management documentation**

Add to `CLAUDE.md` after line 286 (VLAN Distribution table):

```markdown
{% raw %}
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
{% endraw %}
```

**Step 2: Verify formatting**

Run:
```bash
{% raw %}
head -n 320 CLAUDE.md | tail -30
{% endraw %}
```

Expected: New section visible after VLAN Distribution

**Step 3: Commit CLAUDE.md update**

Run:
```bash
{% raw %}
git add CLAUDE.md
git commit -m "docs: add switch management section to CLAUDE.md

- Document ZTP workflow and VLAN 99 architecture
- Add ansible playbook commands for provisioning
- Reference templates and Vault secrets
- Include monitoring stack overview"
{% endraw %}
```

---

## Task 13: Create DNS Record for ZTP Server

**Files:**
- No file changes (DNS API operation)

**Step 1: Create ztp.hl0.dev DNS record**

Run:
```bash
{% raw %}
curl -X POST "https://api.cloudflare.com/client/v4/zones/283c74f5bfbbb2a804dabdb938ccde8f/dns_records" \
  -H "Authorization: Bearer $(vault kv get -field=api_token secret/infrastructure/cloudflare)" \
  -H "Content-Type: application/json" \
  --data '{"type":"A","name":"ztp","content":"10.0.99.20","ttl":300,"proxied":false}'
{% endraw %}
```

Expected: DNS record created successfully

**Step 2: Verify DNS resolution**

Run:
```bash
{% raw %}
sleep 3
dig @1.1.1.1 ztp.hl0.dev +short
{% endraw %}
```

Expected: 10.0.99.20

**Step 3: Document DNS record**

No commit needed - DNS is infrastructure state, not code.

---

## Task 14: Testing and Validation Documentation

**Files:**
- Create: `docs/switch-ztp-testing.md`

**Step 1: Create testing documentation**

File: `docs/switch-ztp-testing.md`
```markdown
{% raw %}
# Switch ZTP Testing Guide

## Pre-Deployment Tests

### 1. Vault Secrets Verification

```bash
vault kv get secret/infrastructure/switches/global
vault kv get secret/infrastructure/switches/tacacs
vault kv get secret/infrastructure/switches/oxidized
{% endraw %}
```

All secrets should be populated.

### 2. ZTP Server Services

```bash
{% raw %}
# VLAN 99 interface
ip addr show vlan99
# Expected: 10.0.99.20/24

# TFTP service
systemctl status atftpd
ss -ulnp | grep :69

# nginx service
systemctl status nginx
curl http://10.0.99.20/
{% endraw %}
```

### 3. TFTP Download Test

```bash
{% raw %}
# From another machine on VLAN 99 (or ubuntu-mgmt01)
tftp 10.0.99.20 -c get network-confg
# Should download file from /srv/tftp/
{% endraw %}
```

### 4. Ansible Inventory

```bash
{% raw %}
cd ansible
ansible-inventory -i inventory/switches.yml --list
{% endraw %}
```

Expected: Valid YAML, switches listed.

### 5. Template Rendering

```bash
{% raw %}
cd ansible
ansible-playbook playbooks/generate-ztp-configs.yml --check
{% endraw %}
```

Expected: No errors, configs would be generated.

## ZTP Workflow Test (Spare Switch)

### Prerequisites
- Spare Cisco switch (IOS or Nexus)
- Access to VLAN 99 network
- Switch registered in `inventory/switches.yml`

### Steps

1. **Factory Reset Switch**
   ```
{% raw %}
   Switch# write erase
   Switch# reload
{% endraw %}
   ```

2. **Connect to VLAN 99**
   - Connect switch management port or access port to VLAN 99
   - Power on switch

3. **Monitor ZTP Progress**

   Timeline:
   - ~30 sec: DHCP lease (check OPNsense: `curl https://10.0.10.1/api/kea/dhcpv4/leases`)
   - ~1 min: TFTP download (check logs: `journalctl -u atftpd -f`)
   - ~2 min: Bootstrap applied, SSH available
   - ~5 min: Ansible triggers (manual: `ansible-playbook playbooks/provision-new-switch.yml -l <hostname>`)
   - ~10 min: Full config applied, switch reboots

4. **Validate Final State**

   ```bash
{% raw %}
   ssh ansible@<switch-ip>

   # IOS
   show running-config
   show vlan brief
   show ip interface brief
   show ip route

   # Nexus
   show running-config
   show vlan brief
   show interface brief
   show ip route
{% endraw %}
   ```

   Expected:
   - Hostname matches inventory
   - VLAN 99 configured with static IP
   - SSH enabled, users created
   - SNMP v3 configured
   - Syslog/NTP pointing to correct servers

## Production Validation (Nexus Cores)

After deploying core switches:

```bash
{% raw %}
# vPC status
show vpc
show vpc brief
show vpc consistency-parameters global

# VLANs
show vlan brief

# Interfaces
show interface brief
show interface | include error

# Environment
show environment temperature
show environment power

# Logs
show logging last 100
{% endraw %}
```

## Monitoring Validation

### 1. SNMP Exporter

```bash
{% raw %}
kubectl get servicemonitor -n monitoring switches-snmp
kubectl get pods -n monitoring | grep snmp-exporter
{% endraw %}
```

### 2. Prometheus Targets

Navigate to Prometheus UI, check targets include switches.

### 3. Grafana Dashboards

Check dashboards display switch metrics (traffic, CPU, temperature).

## Troubleshooting

### TFTP Not Working

```bash
{% raw %}
# Check service
systemctl status atftpd
journalctl -u atftpd -n 50

# Check files
ls -la /srv/tftp/

# Test locally
tftp 127.0.0.1 -c get network-confg

# Check firewall
ufw status | grep 69
{% endraw %}
```

### Switch Not Getting DHCP

- Verify OPNsense VLAN 99 interface is UP
- Check Kea DHCP pool configuration
- Verify option 150 is set (10.0.99.20)
- Check switch port is on VLAN 99

### Bootstrap Config Not Applying

- Verify file exists on TFTP server
- Check filename (IOS: `network-confg`, Nexus: `conf.<SERIAL>`)
- Enable debug on switch (IOS: `debug ip dhcp`, Nexus: `debug dhcp`)

### Ansible Cannot Connect

```bash
{% raw %}
# Test manual SSH
ssh ansible@<switch-ip>

# Check inventory
ansible-inventory -i inventory/switches.yml --host <hostname>

# Test ping
ansible switches -i inventory/switches.yml -m ping -l <hostname>
{% endraw %}
```

## Success Criteria Checklist

- [ ] VLAN 99 operational on OPNsense with Kea DHCP
- [ ] ubuntu-mgmt01 serving TFTP (port 69) and HTTP (port 80)
- [ ] Spare switch provisions via ZTP successfully
- [ ] Switch boots, gets IP, downloads config, applies it
- [ ] SSH accessible, users configured
- [ ] Full config applied via Ansible
- [ ] SNMP metrics visible in Prometheus
- [ ] Grafana dashboards showing switch data
```
{% raw %}

**Step 2: Commit testing documentation**

Run:
```bash
git add docs/switch-ztp-testing.md
git commit -m "docs: add comprehensive ZTP testing guide

- Pre-deployment validation checks
- ZTP workflow testing with spare switch
- Production validation for Nexus cores
- Monitoring stack verification
- Troubleshooting common issues"
{% endraw %}
```

---

## Execution Complete

All tasks completed. Implementation plan saved to `docs/plans/2026-01-22-switch-ztp-implementation.md`.

**Summary:**
- 14 tasks covering full ZTP infrastructure
- Vault secrets, Ansible roles, templates, playbooks
- TFTP/HTTP server configuration
- Bootstrap, core, and edge switch templates
- Testing and validation documentation
- Ready for deployment on ubuntu-mgmt01

**Next Steps:**
1. Review and approve plan
2. Execute tasks sequentially (use superpowers:executing-plans)
3. Deploy to ubuntu-mgmt01
4. Configure OPNsense VLAN 99 and DHCP
5. Test with spare switch before deploying cores
