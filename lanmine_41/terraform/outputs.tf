output "vm_ips" {
  description = "IP addresses of managed VMs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => vm.initialization[0].ip_config[0].ipv4[0].address
  }
}

output "vm_ids" {
  description = "Proxmox VM IDs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => vm.vm_id
  }
}

output "vm_names" {
  description = "VM names"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => vm.name
  }
}

# Talos Kubernetes cluster outputs
output "talos_ips" {
  description = "IP addresses of Talos nodes"
  value = {
    for name, vm in proxmox_virtual_environment_vm.talos :
    name => vm.initialization[0].ip_config[0].ipv4[0].address
  }
}

output "talos_controlplane_ip" {
  description = "Talos control plane IP (for talosctl endpoint)"
  value       = proxmox_virtual_environment_vm.talos["cp1"].initialization[0].ip_config[0].ipv4[0].address
}
