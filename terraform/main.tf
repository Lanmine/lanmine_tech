terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "= 3.0.2-rc06"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "vault" {
  name        = "vault-01"
  vmid        = 9110
  target_node = "proxmox01"
  desc        = "HashiCorp Vault server"

  clone      = "ubuntu-24.04-template"
  full_clone = true
  vm_state   = "running"
  agent      = 1

  memory  = 4096
  sockets = 1
  cores   = 2

  scsihw = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = "50G"
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
    tag    = 10
  }

  # Cloud-init
  os_type    = "cloud-init"
  ipconfig0  = "ip=10.0.10.21/24,gw=10.0.10.1"
  nameserver = "10.0.10.1"
  sshkeys    = var.ssh_public_key

  lifecycle {
    ignore_changes = [network, sshkeys]
  }
}

resource "proxmox_vm_qemu" "runner" {
  name        = "runner-01"
  vmid        = 9120
  target_node = "proxmox01"
  desc        = "GitHub Actions Runner"

  clone      = "ubuntu-24.04-template"
  full_clone = true
  vm_state   = "running"
  agent      = 1

  memory  = 8192
  sockets = 1
  cores   = 4

  scsihw = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = "50G"
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
    tag    = 10
  }

  # Cloud-init
  os_type    = "cloud-init"
  ipconfig0  = "ip=10.0.10.22/24,gw=10.0.10.1"
  nameserver = "10.0.10.1"
  sshkeys    = var.ssh_public_key

  lifecycle {
    ignore_changes = [network, sshkeys]
  }
}
