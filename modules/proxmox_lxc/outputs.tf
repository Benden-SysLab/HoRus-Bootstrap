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

output "guest_baseline_completed" {
  value       = terraform_data.guest_baseline.id
  description = "Pre-start barrier: unique SSH identity, Europe/Moscow and Jenkins sudo verified"
}
