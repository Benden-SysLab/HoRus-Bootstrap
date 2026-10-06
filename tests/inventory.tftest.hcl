variables {
  pmx_api_url   = "https://127.0.0.1:8006/api2/json"
  pmx_api_token = "test@pam!terraform=00000000-0000-0000-0000-000000000000"
}

run "authoritative_inventory_and_boundaries" {
  command = plan

  assert {
    condition     = length(local.workloads) == 28 && length(local.lxc_workloads) == 21 && length(local.vm_workloads) == 7
    error_message = "Expected 28 workloads: 21 LXC and 7 VM."
  }
  assert {
    condition = {
      for node in keys(local.nodes) : node => length([for workload in values(local.workloads) : workload if workload.target_node == node])
      } == {
      "horus-pmx-node01" = 7
      "horus-pmx-node02" = 9
      "horus-pmx-node03" = 6
      "horus-pmx-node04" = 6
    }
    error_message = "Per-node workload counts changed."
  }
  assert {
    condition     = alltrue([for workload in values(local.workloads) : cidrhost(workload.ip_address, 1) == local.vlans[tostring(workload.vlan_id)].gateway])
    error_message = "A VLAN gateway differs from the central map."
  }
  assert {
    condition     = local.lxc_template.vm_id == 9001 && local.lxc_template.datastore_id == "storage-infra" && local.lxc_template.node_name == "horus-pmx-node03" && local.vm_template.vm_id == 9000
    error_message = "Golden source metadata changed."
  }
  assert {
    condition     = alltrue([for workload in values(local.lxc_workloads) : tonumber(workload.disk_size) >= 8]) && alltrue([for workload in values(local.vm_workloads) : tonumber(workload.disk_size) >= 12])
    error_message = "A workload root is smaller than its Golden baseline."
  }
  assert {
    condition     = length(try(local.workloads["horus-ai-srv01"].private_mounts, [])) == 0 && alltrue([for mount in local.private_mounts : local.storage_inventory[mount.storage_name].category == "private"])
    error_message = "Private database data is exposed to an unrelated workload."
  }
  assert {
    condition     = alltrue([for mount in local.shared_mounts : local.storage_inventory[mount.storage_name].category == "shared"]) && length(local.shared_mounts) == 3
    error_message = "Shared media/artifacts must remain guest-level NFS metadata."
  }
  assert {
    condition     = !can(regex("192\\.168\\.", jsonencode(local.workloads))) && !contains(keys(local.storage_inventory), "storage-work") && !contains(keys(local.storage_inventory), "storage-ai") && !contains(keys(local.storage_inventory), "storage-logs")
    error_message = "Legacy network/storage names remain."
  }
  assert {
    condition     = !contains(keys(local.workloads), "horus-ai-srv04") && !contains(keys(local.workloads), "horus-gg-srv01") && !contains([for workload in values(local.workloads) : workload.vmid], 307)
    error_message = "Retired workload names or reserved VMID 307 returned."
  }
  assert {
    condition     = local.local_lvm_logical_root_gib["horus-pmx-node01"] == 124 && local.local_lvm_logical_root_gib["horus-pmx-node02"] == 136 && local.local_lvm_logical_root_gib["horus-pmx-node03"] == 100 && local.local_lvm_logical_root_gib["horus-pmx-node04"] == 78
    error_message = "Capacity arithmetic changed."
  }
}
