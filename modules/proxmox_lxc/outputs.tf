output "lxc_features" {
  value = {
    hostname = var.hostname
    profile  = var.feature_profile
    resolved = local.final_features
  }
}

output "lifecycle_completed" {
  value       = terraform_data.placement.id
  description = "Completion barrier: final node/rootfs/size/configuration verified and CT started"
}

output "ssh_identity_completed" {
  value       = terraform_data.ssh_identity.id
  description = "Completion barrier: workload ED25519 host key differs from Golden LXC 9001"
}

output "guest_baseline_completed" {
  value       = terraform_data.guest_baseline.id
  description = "Completion barrier: Europe/Moscow and Jenkins deployment sudo verified"
}
