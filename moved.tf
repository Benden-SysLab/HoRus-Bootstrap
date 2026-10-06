# The current state contains one real Proxmox workload: LXC VMID 101.
# This is an address-only move of that same object. Historical hostname-based
# mappings are intentionally not retained.
moved {
  from = module.workload_101.module.lxc[0].proxmox_virtual_environment_container.lxc_node
  to   = module.lxc_containers["horus-lb-srv01"].proxmox_virtual_environment_container.lxc_node
}
