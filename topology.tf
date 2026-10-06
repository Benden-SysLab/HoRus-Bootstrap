# Authoritative HoRus cluster topology. Workloads are declared exactly once.

locals {
  nodes = {
    "horus-pmx-node01" = { management_ip = var.environment.management.nodes["horus-pmx-node01"], ram_mb = 31785, local_lvm_gib = 130.27 }
    "horus-pmx-node02" = { management_ip = var.environment.management.nodes["horus-pmx-node02"], ram_mb = 31785, local_lvm_gib = 49.34 }
    "horus-pmx-node03" = { management_ip = var.environment.management.nodes["horus-pmx-node03"], ram_mb = 15953, local_lvm_gib = 53.93 }
    "horus-pmx-node04" = { management_ip = var.environment.management.nodes["horus-pmx-node04"], ram_mb = 15912, local_lvm_gib = 53.93 }
  }

  vlans = {
    "101" = { name = "INFRA", cidr = var.environment.vlan_networks["101"].cidr, gateway = var.environment.vlan_networks["101"].gateway }
    "110" = { name = "TRUSTED", cidr = var.environment.vlan_networks["110"].cidr, gateway = var.environment.vlan_networks["110"].gateway }
    "120" = { name = "IOT", cidr = var.environment.vlan_networks["120"].cidr, gateway = var.environment.vlan_networks["120"].gateway }
    "130" = { name = "QUARANTINE", cidr = var.environment.vlan_networks["130"].cidr, gateway = var.environment.vlan_networks["130"].gateway }
    "140" = { name = "STORAGE", cidr = var.environment.vlan_networks["140"].cidr, gateway = var.environment.vlan_networks["140"].gateway }
    "150" = { name = "OBS/SEC", cidr = var.environment.vlan_networks["150"].cidr, gateway = var.environment.vlan_networks["150"].gateway }
    "160" = { name = "AI", cidr = var.environment.vlan_networks["160"].cidr, gateway = var.environment.vlan_networks["160"].gateway }
    "170" = { name = "DMZ", cidr = var.environment.vlan_networks["170"].cidr, gateway = var.environment.vlan_networks["170"].gateway }
    "180" = { name = "K8S-LAB", cidr = var.environment.vlan_networks["180"].cidr, gateway = var.environment.vlan_networks["180"].gateway }
  }

  vm_template  = { vm_id = 9000, node_name = "horus-pmx-node03", datastore_id = "local-lvm", root_gib = 12 }
  lxc_template = { vm_id = 9001, node_name = "horus-pmx-node03", datastore_id = "storage-infra", root_gib = 8 }

  target_root_datastore = "local-lvm"

  # Private storages allocate one Proxmox-managed volume per workload. A size
  # of 0 creates a managed directory on a directory/NFS backend: no arbitrary
  # host bind mount and no guessed UID/GID mapping are required.
  storage_inventory = {
    "guardian-data" = {
      category          = "private"
      datastore_id      = "guardian-data"
      physical_owner    = "horus-pmx-node01"
      physical_path     = var.environment.storage_paths["guardian-data"]
      terraform_managed = true
    }
    "mimir-data" = {
      category          = "private"
      datastore_id      = "mimir-data"
      physical_owner    = "horus-pmx-node02"
      physical_path     = var.environment.storage_paths["mimir-data"]
      terraform_managed = true
    }
    "infra-data" = {
      category          = "private"
      datastore_id      = "storage-infra"
      physical_owner    = "horus-pmx-node03"
      physical_path     = var.environment.storage_paths["infra"]
      terraform_managed = false
    }
    "artifacts-data" = {
      category          = "private"
      datastore_id      = "artifacts-data"
      physical_owner    = "horus-pmx-node03"
      physical_path     = var.environment.storage_paths["artifacts"]
      terraform_managed = true
    }
    "logs-data" = {
      category          = "private"
      datastore_id      = "logs-data"
      physical_owner    = "horus-pmx-node04"
      physical_path     = var.environment.storage_paths["logs"]
      terraform_managed = true
    }
    "media" = {
      category          = "shared"
      physical_owner    = "horus-pmx-node03"
      physical_path     = var.environment.storage_paths["media"]
      nfs_server        = var.environment.nfs["media"].server
      nfs_export        = var.environment.nfs["media"].export
      allowed_workloads = ["horus-media-srv01", "horus-media-srv02"]
    }
    "artifacts" = {
      category          = "shared"
      physical_owner    = "horus-pmx-node03"
      physical_path     = var.environment.storage_paths["artifacts"]
      nfs_server        = var.environment.nfs["artifacts"].server
      nfs_export        = var.environment.nfs["artifacts"].export
      allowed_workloads = ["horus-agent-srv01"]
    }
  }

  workloads = {
    "horus-lb-srv01"    = { vmid = 101, hostname = "horus-lb-srv01", type = "lxc", target_node = "horus-pmx-node01", cores = 1, memory = 1024, disk_size = "12", ip_address = var.environment.workload_ips["horus-lb-srv01"], vlan_id = 170, feature_profile = "standard" }
    "horus-agent-srv01" = { vmid = 102, hostname = "horus-agent-srv01", type = "lxc", target_node = "horus-pmx-node01", cores = 4, memory = 4096, disk_size = "20", ip_address = var.environment.workload_ips["horus-agent-srv01"], vlan_id = 101, feature_profile = "docker", shared_datasets = [{ storage_name = "artifacts", path = var.environment.guest_paths["artifacts-shared"], read_only = false }] }
    "horus-jnk-srv01"   = { vmid = 103, hostname = "horus-jnk-srv01", type = "vm", target_node = "horus-pmx-node01", cores = 2, memory = 4096, disk_size = "20", ip_address = var.environment.workload_ips["horus-jnk-srv01"], vlan_id = 101 }
    "horus-ai-srv01"    = { vmid = 104, hostname = "horus-ai-srv01", type = "lxc", target_node = "horus-pmx-node01", cores = 4, memory = 6144, disk_size = "20", ip_address = var.environment.workload_ips["horus-ai-srv01"], vlan_id = 150, feature_profile = "standard" }
    "horus-db-srv01"    = { vmid = 105, hostname = "horus-db-srv01", type = "lxc", target_node = "horus-pmx-node01", cores = 2, memory = 2048, disk_size = "16", ip_address = var.environment.workload_ips["horus-db-srv01"], vlan_id = 150, feature_profile = "standard", private_mounts = [{ storage_name = "guardian-data", path = var.environment.guest_paths["guardian-data"], size = "0" }] }
    "horus-media-srv01" = { vmid = 106, hostname = "horus-media-srv01", type = "vm", target_node = "horus-pmx-node01", cores = 2, memory = 4096, disk_size = "20", ip_address = var.environment.workload_ips["horus-media-srv01"], vlan_id = 101, shared_datasets = [{ storage_name = "media", path = var.environment.guest_paths["media"], read_only = false }] }
    "horus-k8sw-srv01"  = { vmid = 107, hostname = "horus-k8sw-srv01", type = "vm", target_node = "horus-pmx-node01", cores = 3, memory = 3072, disk_size = "16", ip_address = var.environment.workload_ips["horus-k8sw-srv01"], vlan_id = 180 }

    "horus-ans-srv01"   = { vmid = 201, hostname = "horus-ans-srv01", type = "lxc", target_node = "horus-pmx-node02", cores = 2, memory = 2048, disk_size = "12", ip_address = var.environment.workload_ips["horus-ans-srv01"], vlan_id = 101, feature_profile = "standard" }
    "horus-ai-srv02"    = { vmid = 202, hostname = "horus-ai-srv02", type = "lxc", target_node = "horus-pmx-node02", cores = 4, memory = 6144, disk_size = "20", ip_address = var.environment.workload_ips["horus-ai-srv02"], vlan_id = 160, feature_profile = "standard", private_mounts = [{ storage_name = "mimir-data", path = var.environment.guest_paths["mimir-data"], size = "0" }] }
    "horus-db-srv02"    = { vmid = 203, hostname = "horus-db-srv02", type = "lxc", target_node = "horus-pmx-node02", cores = 4, memory = 4096, disk_size = "16", ip_address = var.environment.workload_ips["horus-db-srv02"], vlan_id = 160, feature_profile = "standard", private_mounts = [{ storage_name = "mimir-data", path = var.environment.guest_paths["mimir-postgres"], size = "0" }] }
    "horus-vec-srv01"   = { vmid = 204, hostname = "horus-vec-srv01", type = "lxc", target_node = "horus-pmx-node02", cores = 4, memory = 3072, disk_size = "16", ip_address = var.environment.workload_ips["horus-vec-srv01"], vlan_id = 160, feature_profile = "standard", private_mounts = [{ storage_name = "mimir-data", path = var.environment.guest_paths["mimir-vectors"], size = "0" }] }
    "horus-cache-srv01" = { vmid = 205, hostname = "horus-cache-srv01", type = "lxc", target_node = "horus-pmx-node02", cores = 2, memory = 1024, disk_size = "12", ip_address = var.environment.workload_ips["horus-cache-srv01"], vlan_id = 160, feature_profile = "standard" }
    "horus-iam-srv01"   = { vmid = 206, hostname = "horus-iam-srv01", type = "lxc", target_node = "horus-pmx-node02", cores = 2, memory = 2048, disk_size = "12", ip_address = var.environment.workload_ips["horus-iam-srv01"], vlan_id = 101, feature_profile = "standard" }
    "horus-media-srv02" = { vmid = 207, hostname = "horus-media-srv02", type = "lxc", target_node = "horus-pmx-node02", cores = 2, memory = 2048, disk_size = "16", ip_address = var.environment.workload_ips["horus-media-srv02"], vlan_id = 101, feature_profile = "storage", shared_datasets = [{ storage_name = "media", path = var.environment.guest_paths["media"], read_only = false }] }
    "horus-k8sw-srv02"  = { vmid = 208, hostname = "horus-k8sw-srv02", type = "vm", target_node = "horus-pmx-node02", cores = 3, memory = 3072, disk_size = "16", ip_address = var.environment.workload_ips["horus-k8sw-srv02"], vlan_id = 180 }
    "horus-k8sc-srv01"  = { vmid = 209, hostname = "horus-k8sc-srv01", type = "vm", target_node = "horus-pmx-node02", cores = 2, memory = 3072, disk_size = "16", ip_address = var.environment.workload_ips["horus-k8sc-srv01"], vlan_id = 180 }

    "horus-db-srv03"   = { vmid = 301, hostname = "horus-db-srv03", type = "lxc", target_node = "horus-pmx-node03", cores = 2, memory = 2560, disk_size = "16", ip_address = var.environment.workload_ips["horus-db-srv03"], vlan_id = 101, feature_profile = "standard", private_mounts = [{ storage_name = "infra-data", path = var.environment.guest_paths["infra-postgres"], size = "0" }] }
    "horus-vlt-srv01"  = { vmid = 302, hostname = "horus-vlt-srv01", type = "vm", target_node = "horus-pmx-node03", cores = 2, memory = 1536, disk_size = "16", ip_address = var.environment.workload_ips["horus-vlt-srv01"], vlan_id = 101 }
    "horus-wiki-srv01" = { vmid = 303, hostname = "horus-wiki-srv01", type = "lxc", target_node = "horus-pmx-node03", cores = 1, memory = 768, disk_size = "12", ip_address = var.environment.workload_ips["horus-wiki-srv01"], vlan_id = 101, feature_profile = "standard", private_mounts = [{ storage_name = "infra-data", path = var.environment.guest_paths["infra-wiki"], size = "0" }] }
    "horus-git-srv01"  = { vmid = 304, hostname = "horus-git-srv01", type = "lxc", target_node = "horus-pmx-node03", cores = 2, memory = 1536, disk_size = "12", ip_address = var.environment.workload_ips["horus-git-srv01"], vlan_id = 101, feature_profile = "standard", private_mounts = [{ storage_name = "infra-data", path = var.environment.guest_paths["infra-gitea"], size = "0" }] }
    "horus-work-srv01" = { vmid = 305, hostname = "horus-work-srv01", type = "vm", target_node = "horus-pmx-node03", cores = 2, memory = 2048, disk_size = "16", ip_address = var.environment.workload_ips["horus-work-srv01"], vlan_id = 101 }
    "horus-reg-srv01"  = { vmid = 306, hostname = "horus-reg-srv01", type = "lxc", target_node = "horus-pmx-node03", cores = 2, memory = 2048, disk_size = "16", ip_address = var.environment.workload_ips["horus-reg-srv01"], vlan_id = 101, feature_profile = "standard", private_mounts = [{ storage_name = "artifacts-data", path = var.environment.guest_paths["artifacts-registry"], size = "0" }] }

    "horus-grf-srv01"  = { vmid = 401, hostname = "horus-grf-srv01", type = "lxc", target_node = "horus-pmx-node04", cores = 1, memory = 1024, disk_size = "10", ip_address = var.environment.workload_ips["horus-grf-srv01"], vlan_id = 150, feature_profile = "standard" }
    "horus-pm-srv01"   = { vmid = 402, hostname = "horus-pm-srv01", type = "lxc", target_node = "horus-pmx-node04", cores = 2, memory = 2048, disk_size = "12", ip_address = var.environment.workload_ips["horus-pm-srv01"], vlan_id = 150, feature_profile = "standard" }
    "horus-lok-srv01"  = { vmid = 403, hostname = "horus-lok-srv01", type = "lxc", target_node = "horus-pmx-node04", cores = 2, memory = 2048, disk_size = "12", ip_address = var.environment.workload_ips["horus-lok-srv01"], vlan_id = 150, feature_profile = "standard" }
    "horus-otel-srv01" = { vmid = 404, hostname = "horus-otel-srv01", type = "lxc", target_node = "horus-pmx-node04", cores = 1, memory = 1024, disk_size = "12", ip_address = var.environment.workload_ips["horus-otel-srv01"], vlan_id = 150, feature_profile = "standard" }
    "horus-s3-srv01"   = { vmid = 405, hostname = "horus-s3-srv01", type = "lxc", target_node = "horus-pmx-node04", cores = 2, memory = 2048, disk_size = "16", ip_address = var.environment.workload_ips["horus-s3-srv01"], vlan_id = 150, feature_profile = "storage", private_mounts = [{ storage_name = "logs-data", path = var.environment.guest_paths["logs"], size = "0" }] }
    "horus-ai-srv03"   = { vmid = 406, hostname = "horus-ai-srv03", type = "lxc", target_node = "horus-pmx-node04", cores = 2, memory = 2048, disk_size = "16", ip_address = var.environment.workload_ips["horus-ai-srv03"], vlan_id = 150, feature_profile = "standard" }
  }

  lxc_workloads = { for name, workload in local.workloads : name => workload if workload.type == "lxc" }
  vm_workloads  = { for name, workload in local.workloads : name => workload if workload.type == "vm" }

  managed_private_storages = {
    for name, storage in local.storage_inventory : name => storage
    if storage.category == "private" && try(storage.terraform_managed, false)
  }
  private_mounts = flatten([
    for name, workload in local.lxc_workloads : [
      for mount in try(workload.private_mounts, []) : merge(mount, { workload = name, target_node = workload.target_node })
    ]
  ])
  shared_mounts = flatten([
    for name, workload in local.workloads : [
      for mount in try(workload.shared_datasets, []) : merge(mount, { workload = name })
    ]
  ])

  node_ram_allocated_mb = {
    for node in keys(local.nodes) : node => sum([for workload in values(local.workloads) : workload.memory if workload.target_node == node])
  }
  local_lvm_logical_root_gib = {
    for node in keys(local.nodes) : node => sum([for workload in values(local.workloads) : tonumber(workload.disk_size) if workload.target_node == node]) + (node == local.vm_template.node_name ? local.vm_template.root_gib : 0)
  }
  local_lvm_overcommit_ratio = {
    for node, allocated in local.local_lvm_logical_root_gib : node => allocated / local.nodes[node].local_lvm_gib
  }

  environment_coordinates_valid = (
    try(cidrhost("${var.environment.management.gateway}/${split("/", var.environment.management.cidr)[1]}", 0) == cidrhost(var.environment.management.cidr, 0), false) &&
    alltrue([for address in values(var.environment.management.nodes) : try(cidrhost("${address}/${split("/", var.environment.management.cidr)[1]}", 0) == cidrhost(var.environment.management.cidr, 0), false)]) &&
    alltrue([for network in values(var.environment.vlan_networks) : try(cidrhost("${network.gateway}/${split("/", network.cidr)[1]}", 0) == cidrhost(network.cidr, 0), false)]) &&
    alltrue([for workload in values(local.workloads) : try(cidrhost(workload.ip_address, 0) == cidrhost(local.vlans[tostring(workload.vlan_id)].cidr, 0), false)])
  )
}

check "inventory" {
  assert {
    condition     = length(local.workloads) == 28 && length(local.lxc_workloads) == 21 && length(local.vm_workloads) == 7
    error_message = "HoRus inventory must contain exactly 28 workloads: 21 LXC and 7 VM."
  }
}

check "identity_uniqueness" {
  assert {
    condition = (
      length(distinct([for workload in values(local.workloads) : workload.vmid])) == length(local.workloads) &&
      length(distinct([for workload in values(local.workloads) : workload.hostname])) == length(local.workloads)
    )
    error_message = "Workload VMIDs and hostnames must be unique."
  }
}

check "golden_baselines" {
  assert {
    condition     = alltrue([for workload in values(local.workloads) : tonumber(workload.disk_size) >= (workload.type == "vm" ? local.vm_template.root_gib : local.lxc_template.root_gib)])
    error_message = "VM roots must be at least 12 GiB and LXC roots at least 8 GiB."
  }
}

check "placement_and_reserved_ids" {
  assert {
    condition = (
      alltrue([for workload in values(local.workloads) : (
        contains(keys(local.nodes), workload.target_node) &&
        (workload.target_node == "horus-pmx-node01" ? workload.vmid >= 101 && workload.vmid <= 107 :
          workload.target_node == "horus-pmx-node02" ? workload.vmid >= 201 && workload.vmid <= 209 :
          workload.target_node == "horus-pmx-node03" ? workload.vmid >= 301 && workload.vmid <= 306 :
        workload.vmid >= 401 && workload.vmid <= 406)
      )]) &&
      !contains([for workload in values(local.workloads) : workload.vmid], 307) &&
      !contains([for workload in values(local.workloads) : workload.vmid], local.vm_template.vm_id) &&
      !contains([for workload in values(local.workloads) : workload.vmid], local.lxc_template.vm_id)
    )
    error_message = "Every workload must use its approved final-node VMID range; 307, 9000 and 9001 are reserved."
  }
}

check "network" {
  assert {
    condition = alltrue([for workload in values(local.workloads) : try(
      cidrhost(workload.ip_address, 0) == cidrhost(local.vlans[tostring(workload.vlan_id)].cidr, 0) &&
      cidrhost(workload.ip_address, 1) == local.vlans[tostring(workload.vlan_id)].gateway,
      false
    )])
    error_message = "Every workload VLAN must exist and its IP subnet/gateway must match the central VLAN map."
  }
}

check "environment_coordinates" {
  assert {
    condition     = local.environment_coordinates_valid
    error_message = "Management and workload addresses must belong to the configured management/VLAN networks, and every gateway must belong to its network."
  }
}

check "ram_capacity" {
  assert {
    condition     = alltrue([for node, allocated in local.node_ram_allocated_mb : allocated <= local.nodes[node].ram_mb])
    error_message = "Workload RAM allocation exceeds physical node RAM."
  }
}

check "storage_boundaries" {
  assert {
    condition = (
      alltrue([for mount in local.private_mounts : (
        try(local.storage_inventory[mount.storage_name].category, "") == "private" &&
        local.storage_inventory[mount.storage_name].physical_owner == mount.target_node &&
        mount.size == "0"
      )]) &&
      alltrue([for mount in local.shared_mounts : (
        try(local.storage_inventory[mount.storage_name].category, "") == "shared" &&
        contains(try(local.storage_inventory[mount.storage_name].allowed_workloads, []), mount.workload)
      )]) &&
      length(try(local.workloads["horus-ai-srv01"].private_mounts, [])) == 0
    )
    error_message = "Private state must be single-owner Proxmox storage; shared data must remain guest-managed NFS. Guardian AI must not receive Guardian DB files."
  }
}

check "retired_names_absent" {
  assert {
    condition     = alltrue([for retired in ["horus-ai-srv04", "horus-gg-srv01"] : !contains(keys(local.workloads), retired)])
    error_message = "Retired workload names must remain absent."
  }
}

# Keep the accepted thin-provisioning risk explicit and detect any unreviewed
# capacity drift. Workload sizes are not reduced to make this assertion pass.
check "local_lvm_capacity_accounting" {
  assert {
    condition = (
      local.local_lvm_logical_root_gib == {
        "horus-pmx-node01" = 124
        "horus-pmx-node02" = 136
        "horus-pmx-node03" = 100
        "horus-pmx-node04" = 78
      } &&
      local.local_lvm_overcommit_ratio["horus-pmx-node01"] <= 1 &&
      alltrue([for node in ["horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"] : local.local_lvm_overcommit_ratio[node] > 1])
    )
    error_message = "Reviewed local-lvm capacity changed. Recalculate physical capacity and logical thin allocation before apply."
  }
}
