output "lxc_features" {
  value = {
    for k, m in module.lxc_containers : k => m.lxc_features
  }
  description = "Результирующие профили и настройки возможностей всех развернутых LXC-контейнеров платформы HoRus"
}

output "workload_inventory" {
  value = {
    for k, v in local.workloads : k => {
      vmid              = v.vmid
      type              = v.type
      target_node       = v.target_node
      ip_address        = v.ip_address
      cores             = v.cores
      memory_mb         = v.memory
      root_storage      = v.root_storage
      additional_mounts = try(v.additional_mounts, [])
      additional_disks  = try(v.additional_disks, [])
    }
  }
  description = "Полный паспорт и топологическая матрица 22 workload'ов кластера HoRus"
}

output "storage_inventory" {
  value       = local.storage_inventory
  description = "Реестр и топология дисковых хранилищ кластера HoRus с указанием физических владельцев и потребителей"
}
