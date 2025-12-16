terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
    }
  }
}

resource "proxmox_vm_qemu" "this" {
  name        = var.name
  vmid        = var.vmid
  target_node = var.target_node

  vm_state = "running"
  qemu_os  = "l26"
  bios     = "ovmf"
  agent    = 1

  memory = 4096

  cpu {
    cores   = 2
    sockets = 1
  }

  scsihw = "virtio-scsi-single"
  boot   = "order=ide2;scsi0"

  # EFI disk for UEFI boot
  efidisk {
    storage = "local-lvm"
    efitype = "4m"
  }

  # Disks
  disks {
    # Talos boot disk
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = "20"
        }
      }
    }
    # Talos ISO
    ide {
      ide2 {
        cdrom {
          iso = var.iso
        }
      }
    }
  }

  # Network
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
    tag    = var.vlan_tag
  }

  lifecycle {
    ignore_changes = [
      network,
      efidisk,
      full_clone,
      smbios,
    ]
  }
}
