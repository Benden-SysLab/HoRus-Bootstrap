output "lxc_features" {
  value = {
    hostname = var.hostname
    profile  = var.feature_profile
    resolved = {
      nesting = local.final_features.nesting
      keyctl  = local.final_features.keyctl
      fuse    = local.final_features.fuse
      mount   = local.final_features.mount
      mknod   = local.final_features.mknod
    }
  }
  description = "Результирующие настройки возможностей контейнера"
}
