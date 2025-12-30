variable "proxmox_api_url" {
  description = "Proxmox API endpoint (e.g. https://proxmox01:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (only for self-signed certs)"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}
