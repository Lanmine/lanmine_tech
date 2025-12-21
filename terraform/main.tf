terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }

  backend "pg" {
    conn_str = var.pg_conn_str
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
    # Prevent Terraform from destroying VMs not managed by it
    prevent_destroy = true

    # Create before destroy to avoid downtime
    create_before_destroy = true

    # Ignore changes that shouldn't trigger recreation
    ignore_changes = [
      initialization,
      disk,
      network_device,
    ]
  }
}

# Pre-flight check to prevent duplicate VM creation
resource "null_resource" "vault_vm_check" {
  triggers = {
    vm_name = proxmox_virtual_environment_vm.vault.name
    vm_id   = proxmox_virtual_environment_vm.vault.vm_id
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      # Check if VM exists in Proxmox
      if curl -s -k -H "Authorization: PVEAPIToken=${var.proxmox_api_token}" \
         "${var.proxmox_api_url}/api2/json/nodes/${proxmox_virtual_environment_vm.vault.node_name}/qemu" | \
         jq -e '.data[] | select(.name == "${self.triggers.vm_name}")' > /dev/null; then
        echo "WARNING: VM ${self.triggers.vm_name} already exists in Proxmox but not managed by Terraform"
        echo "Consider running: terraform import proxmox_virtual_environment_vm.vault proxmox01/${self.triggers.vm_id}"
      fi
    EOT

    environment = {
      PROXMOX_API_URL   = var.proxmox_api_url
      PROXMOX_API_TOKEN = var.proxmox_api_token
    }
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
    # Prevent Terraform from destroying VMs not managed by it
    prevent_destroy = true

    # Create before destroy to avoid downtime
    create_before_destroy = true

    # Ignore changes that shouldn't trigger recreation
    ignore_changes = [
      initialization,
      disk,
      network_device,
    ]
  }
}

# Pre-flight check to prevent duplicate VM creation
resource "null_resource" "runner_vm_check" {
  triggers = {
    vm_name = proxmox_virtual_environment_vm.runner.name
    vm_id   = proxmox_virtual_environment_vm.runner.vm_id
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      # Check if VM exists in Proxmox
      if curl -s -k -H "Authorization: PVEAPIToken=${var.proxmox_api_token}" \
         "${var.proxmox_api_url}/api2/json/nodes/${proxmox_virtual_environment_vm.runner.node_name}/qemu" | \
         jq -e '.data[] | select(.name == "${self.triggers.vm_name}")' > /dev/null; then
        echo "WARNING: VM ${self.triggers.vm_name} already exists in Proxmox but not managed by Terraform"
        echo "Consider running: terraform import proxmox_virtual_environment_vm.runner proxmox01/${self.triggers.vm_id}"
      fi
    EOT

    environment = {
      PROXMOX_API_URL   = var.proxmox_api_url
      PROXMOX_API_TOKEN = var.proxmox_api_token
    }
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
    # Prevent Terraform from destroying VMs not managed by it
    prevent_destroy = true

    # Create before destroy to avoid downtime
    create_before_destroy = true

    # Ignore changes that shouldn't trigger recreation
    ignore_changes = [
      initialization,
      disk,
      network_device,
    ]
  }
}

# Pre-flight check to prevent duplicate VM creation
resource "null_resource" "vm_check" {
  triggers = {
    vm_name = proxmox_virtual_environment_vm.authentik.name
    vm_id   = proxmox_virtual_environment_vm.authentik.vm_id
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      # Check if VM exists in Proxmox
      if curl -s -k -H "Authorization: PVEAPIToken=${var.proxmox_api_token}" \
         "${var.proxmox_api_url}/api2/json/nodes/${proxmox_virtual_environment_vm.authentik.node_name}/qemu" | \
         jq -e '.data[] | select(.name == "${self.triggers.vm_name}")' > /dev/null; then
        echo "ERROR: VM ${self.triggers.vm_name} already exists in Proxmox"
        echo "Please import the existing VM or remove it first:"
        echo "terraform import proxmox_virtual_environment_vm.authentik proxmox01/${self.triggers.vm_id}"
        exit 1
      fi
      
      # Check if VM ID is already in use
      if curl -s -k -H "Authorization: PVEAPIToken=${var.proxmox_api_token}" \
         "${var.proxmox_api_url}/api2/json/nodes/${proxmox_virtual_environment_vm.authentik.node_name}/qemu" | \
         jq -e '.data[] | select(.vmid == ${self.triggers.vm_id})' > /dev/null; then
        echo "ERROR: VM ID ${self.triggers.vm_id} is already in use in Proxmox"
        echo "Please choose a different VM ID or import the existing VM"
        exit 1
      fi
    EOT

    environment = {
      PROXMOX_API_URL   = var.proxmox_api_url
      PROXMOX_API_TOKEN = var.proxmox_api_token
    }
  }
}
