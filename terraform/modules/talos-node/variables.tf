variable "name" {
  type = string
}

variable "vmid" {
  type = number
}

variable "target_node" {
  type = string
}

variable "vlan_tag" {
  type = number
}

variable "iso" {
  type        = string
  description = "ISO image to boot from (e.g., local:iso/talos.iso)"
}
