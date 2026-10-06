output "workload_inventory" {
  description = "Authoritative HoRus workload inventory"
  value = {
    for name, workload in local.workloads : name => {
      vmid            = workload.vmid
      hostname        = workload.hostname
      type            = workload.type
      target_node     = workload.target_node
      cores           = workload.cores
      memory_mb       = workload.memory
      root_storage    = local.target_root_datastore
      root_size_gib   = tonumber(workload.disk_size)
      ip_address      = workload.ip_address
      vlan_id         = workload.vlan_id
      gateway         = local.vlans[tostring(workload.vlan_id)].gateway
      private_mounts  = try(workload.private_mounts, [])
      shared_datasets = try(workload.shared_datasets, [])
    }
  }
}

output "storage_inventory" {
  description = "Private Proxmox storage and shared guest-NFS ownership boundaries"
  value       = local.storage_inventory
}

output "shared_dataset_manifest" {
  description = "Guest-level NFS metadata for the later Ansible layer; Terraform does not mount it on hosts or guests"
  value = [for mount in local.shared_mounts : {
    workload   = mount.workload
    dataset    = mount.storage_name
    server     = local.storage_inventory[mount.storage_name].nfs_server
    export     = local.storage_inventory[mount.storage_name].nfs_export
    guest_path = mount.path
    read_only  = mount.read_only
  }]
}

output "lxc_placement_manifest" {
  description = "LXC clone/rootfs placement manifest generated from local.workloads"
  value = {
    for name, workload in local.lxc_workloads : name => {
      vmid               = workload.vmid
      source_node        = local.lxc_template.node_name
      source_storage     = local.lxc_template.datastore_id
      final_node         = workload.target_node
      final_root_storage = local.target_root_datastore
      desired_size_gib   = tonumber(workload.disk_size)
    }
  }
}

output "local_lvm_capacity" {
  description = "Logical thin-provisioned root allocation versus physical local-lvm capacity; Node03 includes external VM template 9000"
  value = {
    for node, spec in local.nodes : node => {
      physical_gib     = spec.local_lvm_gib
      logical_root_gib = local.local_lvm_logical_root_gib[node]
      overcommit_ratio = local.local_lvm_overcommit_ratio[node]
      overcommitted    = local.local_lvm_overcommit_ratio[node] > 1
    }
  }
}

output "lxc_features" {
  description = "Resolved feature profile for every LXC workload"
  value       = { for name, module_instance in module.lxc_containers : name => module_instance.lxc_features }
}
