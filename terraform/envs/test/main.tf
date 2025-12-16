# Talos test environment
# Nodes are defined in nodes.auto.tfvars

module "talos_nodes" {
  source   = "../../modules/talos-node"
  for_each = { for node in var.talos_nodes : node.name => node }

  providers = {
    proxmox = proxmox.main
  }

  name        = each.value.name
  vmid        = each.value.vmid
  target_node = var.target_node
  vlan_tag    = var.vlan_tag
  iso         = var.iso
}
