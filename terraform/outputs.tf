output "vault_ip" {
  description = "IP address of the Vault VM"
  value       = "10.0.10.21"
}

output "vault_vmid" {
  description = "Proxmox VM ID of the Vault VM"
  value       = proxmox_vm_qemu.vault.vmid
}

output "vault_name" {
  description = "Name of the Vault VM"
  value       = proxmox_vm_qemu.vault.name
}
