# Existing ext4 roots were verified read-only on their physical owners before
# declaring these storages. create_base_path=false prevents Terraform from
# fabricating a missing physical mount; Proxmox only creates its normal volume
# subdirectories beneath an already-present root.
resource "proxmox_storage_directory" "private" {
  for_each = local.managed_private_storages

  id               = each.value.datastore_id
  path             = each.value.physical_path
  nodes            = [each.value.physical_owner]
  content          = ["rootdir"]
  shared           = false
  disable          = false
  create_base_path = false
  create_subdirs   = true
}

module "lxc_containers" {
  for_each = local.lxc_workloads
  source   = "./modules/proxmox_lxc"

  target_node       = each.value.target_node
  vmid              = each.value.vmid
  hostname          = each.value.hostname
  cores             = each.value.cores
  memory            = each.value.memory
  disk_size         = each.value.disk_size
  root_storage      = local.target_root_datastore
  clone_node        = local.lxc_template.node_name
  clone_template_id = local.lxc_template.vm_id
  clone_storage     = local.lxc_template.datastore_id
  bridge            = "vmbr0"
  vlan_id           = each.value.vlan_id
  ip_address        = each.value.ip_address
  gateway           = local.vlans[tostring(each.value.vlan_id)].gateway
  dns_servers       = var.dns_servers
  feature_profile   = try(each.value.feature_profile, "standard")
  private_mounts = [for mount in try(each.value.private_mounts, []) : {
    datastore_id = local.storage_inventory[mount.storage_name].datastore_id
    path         = mount.path
    size         = mount.size
  }]
  bootstrap_ssh_key_path = var.bootstrap_ssh_key_path
  allow_lxc_shutdown     = var.allow_lxc_shutdown

  depends_on = [proxmox_storage_directory.private]
}

module "virtual_machines" {
  for_each = local.vm_workloads
  source   = "./modules/proxmox_vm"

  target_node       = each.value.target_node
  factory_node      = local.vm_template.node_name
  clone_template_id = local.vm_template.vm_id
  vmid              = each.value.vmid
  hostname          = each.value.hostname
  cores             = each.value.cores
  memory            = each.value.memory
  disk_size         = each.value.disk_size
  root_storage      = local.target_root_datastore
  bridge            = "vmbr0"
  vlan_id           = each.value.vlan_id
  ip_address        = each.value.ip_address
  gateway           = local.vlans[tostring(each.value.vlan_id)].gateway
  dns_servers       = var.dns_servers
}
