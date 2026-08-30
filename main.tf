# ==============================================================================
# ЛОКАЛЬНОЕ ХРАНЕНИЕ СЕКРЕТОВ (Исключено из репозитория через .gitignore)
# ==============================================================================

locals {
  # Считываем root-пароль из локального файла root_password.txt, который добавлен в .gitignore.
  # Функция trimspace удаляет случайные переводы строк или пробелы.
  root_password = trimspace(file("${path.module}/root_password.txt"))
}

# ==============================================================================
# PROXMOX LXC CONTAINERS (Direct LXC Template Provisioning)
# ==============================================================================

module "lxc_containers" {
  for_each = {
    for k, v in local.workloads : k => v if v.type == "lxc"
  }

  source            = "./modules/proxmox_lxc"
  target_node       = each.value.target_node
  vmid              = each.value.vmid
  hostname          = each.value.hostname
  cores             = each.value.cores
  memory            = each.value.memory
  disk_size         = try(each.value.disk_size, "32")
  root_storage      = try(each.value.root_storage, "local-lvm")
  bridge            = try(each.value.bridge, "vmbr0")
  vlan_id           = try(each.value.vlan_id, 0)
  ip_address        = each.value.ip_address
  gateway           = var.gateway_ip
  dns_servers       = var.dns_servers
  ssh_public_key    = var.ssh_public_key
  root_password     = local.root_password
  ostemplate        = try(each.value.image_source, local.lxc_template_file_id)
  feature_profile   = try(each.value.feature_profile, "standard")
  additional_mounts = try(each.value.additional_mounts, [])
}

# ==============================================================================
# PROXMOX VIRTUAL MACHINES (Golden VM 9000 Clone Provisioning)
# ==============================================================================

module "virtual_machines" {
  for_each = {
    for k, v in local.workloads : k => v if v.type == "vm"
  }

  source            = "./modules/proxmox_vm"
  target_node       = each.value.target_node
  factory_node      = try(each.value.factory_node, "horus-pmx-node03")
  vmid              = each.value.vmid
  hostname          = each.value.hostname
  cores             = each.value.cores
  memory            = each.value.memory
  disk_size         = try(each.value.disk_size, "32")
  root_storage      = try(each.value.root_storage, "local-lvm")
  bridge            = try(each.value.bridge, "vmbr0")
  vlan_id           = try(each.value.vlan_id, 0)
  ip_address        = each.value.ip_address
  gateway           = var.gateway_ip
  dns_servers       = var.dns_servers
  ssh_public_key    = var.ssh_public_key
  root_password     = local.root_password
  clone_template_id = try(each.value.clone_template_id, 9000)
  additional_disks  = try(each.value.additional_disks, [])
}
