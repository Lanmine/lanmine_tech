terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.75"
    }
  }

  # Backend configuration is supplied at init time:
  # terraform init -backend-config="conn_str=..."
  backend "pg" {}
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # Skip waiting for QEMU guest agent (speeds up plan/apply significantly)
  ssh {
    agent = false
  }
}

###############################################################################
# VM inventory (single source of truth)
###############################################################################

locals {
  # Talos Kubernetes cluster nodes
  talos_nodes = {
    cp1 = {
      name        = "talos-cp-01"
      vm_id       = 9200
      cpu         = 2
      memory      = 4096
      ip          = "10.0.10.30/24"
      role        = "controlplane"
      description = "Talos Kubernetes control plane"
    }

    worker1 = {
      name        = "talos-worker-01"
      vm_id       = 9201
      cpu         = 4
      memory      = 8192
      ip          = "10.0.10.31/24"
      role        = "worker"
      description = "Talos Kubernetes worker node"
    }

    worker2 = {
      name        = "talos-worker-02"
      vm_id       = 9202
      cpu         = 4
      memory      = 8192
      ip          = "10.0.10.32/24"
      role        = "worker"
      description = "Talos Kubernetes worker node"
    }
  }

  # Regular VMs (Ubuntu-based)
  vms = {
    vault = {
      name        = "vault-01"
      vm_id       = 9110
      cpu         = 2
      memory      = 4096
      ip          = "10.0.10.21/24"
      tags        = ["infrastructure", "vault"]
      agent       = true
      description = "HashiCorp Vault server"
    }

    runner = {
      name        = "runner-01"
      vm_id       = 9120
      cpu         = 4
      memory      = 8192
      ip          = "10.0.10.22/24"
      tags        = ["infrastructure", "cicd"]
      agent       = false
      description = "GitHub Actions self-hosted runner"
    }

    authentik = {
      name        = "authentik-01"
      vm_id       = 9199
      cpu         = 2
      memory      = 4096
      ip          = "10.0.10.25/24"
      tags        = ["infrastructure", "auth"]
      agent       = true
      description = "Authentik SSO and Identity Provider"
    }

    akvorado = {
      name        = "akvorado-01"
      vm_id       = 9140
      cpu         = 4
      memory      = 16384
      disk_size   = 100
      ip          = "10.0.10.26/24"
      tags        = ["infrastructure", "monitoring"]
      agent       = true
      description = "Akvorado network flow collector"
    }

    n8n = {
      name        = "n8n-01"
      vm_id       = 9150
      cpu         = 4
      memory      = 8192
      ip          = "10.0.10.27/24"
      tags        = ["infrastructure", "automation"]
      agent       = true
      template_id = 9000 # ubuntu-24.04-template
      description = "n8n workflow automation with Azure OpenAI"
    }

    panda9000 = {
      name        = "panda9000-01"
      vm_id       = 9160
      cpu         = 4
      memory      = 8192
      ip          = "10.0.10.28/24"
      tags        = ["infrastructure", "assistant"]
      agent       = true
      template_id = 9000 # ubuntu-24.04-template
      description = "PANDA9000 voice interface"
    }
  }
}

###############################################################################
# Proxmox VMs
###############################################################################

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  name        = each.value.name
  vm_id       = each.value.vm_id
  node_name   = "proxmox01"
  tags        = each.value.tags
  description = each.value.description

  dynamic "clone" {
    for_each = lookup(each.value, "template_id", null) != null ? [1] : []
    content {
      vm_id = each.value.template_id
    }
  }

  agent {
    enabled = each.value.agent
  }

  cpu {
    cores   = each.value.cpu
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    size         = lookup(each.value, "disk_size", 50)
    interface    = "scsi0"
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 10
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = "10.0.10.1"
      }
    }

    dns {
      servers = ["10.0.10.1"]
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    # Absolute safety for critical infrastructure
    prevent_destroy = true

    # Cloud-init is one-shot; drift here is expected
    ignore_changes = [
      initialization,
    ]
  }
}

###############################################################################
# Talos Kubernetes Cluster
###############################################################################

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_nodes

  name        = each.value.name
  vm_id       = each.value.vm_id
  node_name   = "proxmox01"
  tags        = ["kubernetes", each.value.role]
  description = each.value.description

  clone {
    vm_id = 9100 # talos-template
  }

  agent {
    enabled = false # Talos doesn't run qemu-guest-agent by default
  }

  cpu {
    cores   = each.value.cpu
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    size         = 50
    interface    = "scsi0"
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 10
  }

  # Talos uses machine config, not cloud-init
  # IP will be configured via talosctl apply-config
  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = "10.0.10.1"
      }
    }

    dns {
      servers = ["10.0.10.1"]
    }
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      initialization,
    ]
  }
}
