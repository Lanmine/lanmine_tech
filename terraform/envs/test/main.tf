# Talos test environment
module "talos_test_node" {
  source = "../../modules/talos-node"

  providers = {
    proxmox = proxmox.main
  }

  name        = "talos-test-01"
  vmid        = 9201
  target_node = "proxmox01"
  vlan_tag    = 10
  iso         = "local:iso/talos-v1.11.5-amd64.iso"
}
