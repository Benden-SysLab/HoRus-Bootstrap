provider "proxmox" {
  endpoint  = "https://127.0.0.1:8006/api2/json"
  api_token = "test@pam!terraform=00000000-0000-0000-0000-000000000000"
  insecure  = true
}

variables {
  target_node  = "horus-pmx-node01"
  factory_node = "horus-pmx-node03"
  vmid         = 103
  hostname     = "horus-jnk-srv01"
  cores        = 2
  memory       = 4096
  disk_size    = "20"
  root_storage = "local-lvm"
  bridge       = "vmbr0"
  vlan_id      = 101
  ip_address   = "198.51.100.3/28"
  gateway      = "198.51.100.1"
  dns_servers  = ["203.0.113.53"]
}

run "provider_native_vm_clone" {
  command = plan
  module {
    source = "./modules/proxmox_vm"
  }
  assert {
    condition     = proxmox_virtual_environment_vm.kvm_node.migrate && proxmox_virtual_environment_vm.kvm_node.started && proxmox_virtual_environment_vm.kvm_node.on_boot
    error_message = "VM placement/start must remain provider-native."
  }
  assert {
    condition     = proxmox_virtual_environment_vm.kvm_node.node_name == "horus-pmx-node01" && proxmox_virtual_environment_vm.kvm_node.clone[0].node_name == "horus-pmx-node03" && proxmox_virtual_environment_vm.kvm_node.clone[0].vm_id == 9000
    error_message = "VM Golden source or final node changed."
  }
  assert {
    condition     = length(proxmox_virtual_environment_vm.kvm_node.initialization[0].user_account) == 0
    error_message = "Cloud-Init must not overwrite the Golden security/user baseline."
  }
}

run "vm_cannot_shrink_below_golden" {
  command = plan
  module {
    source = "./modules/proxmox_vm"
  }
  variables {
    disk_size = "8"
  }
  expect_failures = [var.disk_size]
}
