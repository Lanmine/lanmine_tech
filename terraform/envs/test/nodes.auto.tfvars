# Talos Nodes Configuration
# =========================
# Add new nodes by copying a line and changing the name and vmid.
# Then commit this file - the CI/CD will create the VM automatically.
#
# Example:
#   { name = "talos-worker-01", vmid = 9210 },

talos_nodes = [
  { name = "talos-test-01", vmid = 9201 },
]
