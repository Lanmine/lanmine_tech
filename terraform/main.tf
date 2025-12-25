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
    size         = 50
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
