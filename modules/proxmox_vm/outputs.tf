output "lifecycle_completed" {
  value       = proxmox_virtual_environment_vm.kvm_node.id
  description = "Native provider clone/migration/configuration/start completion barrier."
}
