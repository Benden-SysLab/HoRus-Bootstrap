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
