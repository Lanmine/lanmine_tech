variable "talos_nodes" {
  description = "List of Talos nodes to create"
  type = list(object({
    name = string
    vmid = number
  }))
  default = []
}

variable "target_node" {
  description = "Proxmox node to deploy VMs on"
  type        = string
  default     = "proxmox01"
}

variable "vlan_tag" {
  description = "VLAN tag for the network"
  type        = number
  default     = 10
}

variable "iso" {
  description = "Talos ISO image path"
  type        = string
  default     = "local:iso/talos-v1.11.5-amd64.iso"
}
