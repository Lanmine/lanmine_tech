terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }

  backend "pg" {
    # Connection string passed via PG_CONN_STR environment variable
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true
}

resource "proxmox_virtual_environment_vm" "vault" {
  name      = "vault-01"
  vm_id     = 9110
  node_name = "proxmox01"
  tags      = ["infrastructure", "vault"]

  description = "HashiCorp Vault server"

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 4096
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
        address = "10.0.10.21/24"
        gateway = "10.0.10.1"
      }
    }
    dns {
      servers = ["10.0.10.1"]
    }
    user_account {
      keys     = [var.ssh_public_key]
      username = "ubuntu"
    }
  }

  lifecycle {
    ignore_changes = [
      initialization,
      disk,
      network_device,
    ]
  }
}

resource "proxmox_virtual_environment_vm" "runner" {
  name      = "runner-01"
  vm_id     = 9120
  node_name = "proxmox01"
  tags      = ["infrastructure", "cicd"]

  description = "GitHub Actions Runner"

  agent {
    enabled = false
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 8192
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
        address = "10.0.10.22/24"
        gateway = "10.0.10.1"
      }
    }
    dns {
      servers = ["10.0.10.1"]
    }
    user_account {
      keys     = [var.ssh_public_key]
      username = "ubuntu"
    }
  }

  lifecycle {
    ignore_changes = [
      initialization,
      disk,
      network_device,
    ]
  }
}

resource "proxmox_virtual_environment_vm" "authentik" {
  name      = "authentik-01"
  vm_id     = 9199
  node_name = "proxmox01"
  tags      = ["infrastructure", "auth"]

  description = "Authentik SSO and Identity Provider"

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 4096
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
        address = "10.0.10.25/24"
        gateway = "10.0.10.1"
      }
    }
    dns {
      servers = ["10.0.10.1"]
    }
    user_account {
      keys     = [var.ssh_public_key]
      username = "ubuntu"
    }
  }

  lifecycle {
    ignore_changes = [
      initialization,
      disk,
      network_device,
    ]
  }
}
