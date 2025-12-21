variable "pg_conn_str" {
  type        = string
  sensitive   = true
  description = "PostgreSQL connection string for Terraform state backend"
}

variable "proxmox_api_url" {
  type        = string
  sensitive   = true
  description = "Proxmox API URL (e.g., https://proxmox:8006)"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in format: user@realm!tokenid=secret"
}

variable "ssh_public_key" {
  type        = string
  sensitive   = true
  description = "SSH public key for VM access"
}
