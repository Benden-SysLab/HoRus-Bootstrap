# ==============================================================================
# DECLARATIVE WORKLOAD INVENTORY & TOPOLOGY VALIDATION
# ==============================================================================

locals {
  lxc_template_file_id = "storage-infra:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"

  workloads = {
    # --------------------------------------------------------------------------
    # NODE01 (horus-pmx-node01: 8C / 31.04 GiB RAM - GPU, Compute, Deploy, Media Core, LB)
    # --------------------------------------------------------------------------
    "horus-jnk-srv01" = {
      vmid              = 101
      hostname          = "horus-jnk-srv01"
      type              = "vm"
      target_node       = "horus-pmx-node01"
      factory_node      = "horus-pmx-node03"
      cores             = 2
      memory            = 4096
      disk_size         = "32"
      root_storage      = "local-lvm"
      ip_address        = "192.168.1.211/24"
      bridge            = "vmbr0"
      vlan_id           = 0
      image_source      = "9000"
      clone_template_id = 9000
    }
    "horus-ai-srv01" = {
      vmid            = 102
      hostname        = "horus-ai-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node01"
      cores           = 4
      memory          = 4096
      disk_size       = "32"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.212/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-ai-srv02" = {
      vmid            = 103
      hostname        = "horus-ai-srv02"
      type            = "lxc"
      target_node     = "horus-pmx-node01"
      cores           = 4
      memory          = 4096
      disk_size       = "32"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.213/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-media-srv02" = {
      vmid            = 104
      hostname        = "horus-media-srv02"
      type            = "lxc"
      target_node     = "horus-pmx-node01"
      cores           = 4
      memory          = 4096
      disk_size       = "32"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.214/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
      additional_mounts = [
        {
          mount_type   = "bind_mount"
          volume       = "/mnt/pve/.horus-nfs/storage-media"
          mp           = "/storage/media"
          storage_name = "storage-media"
          size         = null
        }
      ]
    }
    "horus-lb-srv01" = {
      vmid            = 105
      hostname        = "horus-lb-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node01"
      cores           = 2
      memory          = 2048
      disk_size       = "10"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.215/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-ans-srv01" = {
      vmid            = 106
      hostname        = "horus-ans-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node01"
      cores           = 2
      memory          = 4096
      disk_size       = "20"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.216/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }

    # --------------------------------------------------------------------------
    # NODE02 (horus-pmx-node02: 8C / 31.04 GiB RAM - IAM, Registry, Build Agent, AI Mimir)
    # --------------------------------------------------------------------------
    "horus-iam-srv01" = {
      vmid            = 201
      hostname        = "horus-iam-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node02"
      cores           = 2
      memory          = 2048
      disk_size       = "20"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.221/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-media-srv01" = {
      vmid            = 202
      hostname        = "horus-media-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node02"
      cores           = 2
      memory          = 2048
      disk_size       = "16"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.222/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "storage"
      additional_mounts = [
        {
          mount_type   = "bind_mount"
          volume       = "/mnt/pve/.horus-nfs/storage"
          mp           = "/storage/files"
          storage_name = "storage"
          size         = null
        },
        {
          mount_type   = "bind_mount"
          volume       = "/mnt/pve/.horus-nfs/storage-media"
          mp           = "/storage/media"
          storage_name = "storage-media"
          size         = null
        }
      ]
    }
    "horus-agent-srv01" = {
      vmid            = 203
      hostname        = "horus-agent-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node02"
      cores           = 4
      memory          = 4096
      disk_size       = "40"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.223/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "docker"
    }
    "horus-gg-srv01" = {
      vmid            = 204
      hostname        = "horus-gg-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node02"
      cores           = 2
      memory          = 2048
      disk_size       = "15"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.224/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-ai-srv03" = {
      vmid            = 205
      hostname        = "horus-ai-srv03"
      type            = "lxc"
      target_node     = "horus-pmx-node02"
      cores           = 4
      memory          = 8192
      disk_size       = "32"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.225/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
      additional_mounts = [
        {
          mount_type   = "dedicated_volume"
          volume       = "storage-ai"
          mp           = "/data-ai"
          storage_name = "storage-ai"
          size         = "400G"
        }
      ]
    }
    "horus-reg-srv01" = {
      vmid            = 206
      hostname        = "horus-reg-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node02"
      cores           = 2
      memory          = 4096
      disk_size       = "40"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.226/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "docker"
    }

    # --------------------------------------------------------------------------
    # NODE03 (horus-pmx-node03: 8C / 15.58 GiB RAM - Factory Node, NAS, DBs, Stateful)
    # --------------------------------------------------------------------------
    "horus-git-srv01" = {
      vmid            = 301
      hostname        = "horus-git-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node03"
      cores           = 2
      memory          = 2048
      disk_size       = "20"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.231/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
      additional_mounts = [
        {
          mount_type   = "dedicated_volume"
          volume       = "storage-work"
          mp           = "/var/lib/gitea"
          storage_name = "storage-work"
          size         = "100G"
        }
      ]
    }
    "horus-vlt-srv01" = {
      vmid              = 302
      hostname          = "horus-vlt-srv01"
      type              = "vm"
      target_node       = "horus-pmx-node03"
      factory_node      = "horus-pmx-node03"
      cores             = 2
      memory            = 2048
      disk_size         = "32"
      root_storage      = "local-lvm"
      ip_address        = "192.168.1.232/24"
      bridge            = "vmbr0"
      vlan_id           = 0
      image_source      = "9000"
      clone_template_id = 9000
      additional_disks = [
        {
          datastore    = "storage-work"
          interface    = "scsi1"
          size         = "50"
          mount_type   = "dedicated_volume"
          storage_name = "storage-work"
        }
      ]
    }
    "horus-wiki-srv01" = {
      vmid            = 303
      hostname        = "horus-wiki-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node03"
      cores           = 1
      memory          = 1024
      disk_size       = "15"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.233/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-db-srv01" = {
      vmid            = 304
      hostname        = "horus-db-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node03"
      cores           = 2
      memory          = 4096
      disk_size       = "30"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.234/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
      additional_mounts = [
        {
          mount_type   = "dedicated_volume"
          volume       = "storage-work"
          mp           = "/var/lib/postgresql/data"
          storage_name = "storage-work"
          size         = "800G"
        }
      ]
    }

    # --------------------------------------------------------------------------
    # NODE04 (horus-pmx-node04: 4C / 15.54 GiB RAM - Observability, S3, AIOps)
    # --------------------------------------------------------------------------
    "horus-grf-srv01" = {
      vmid            = 401
      hostname        = "horus-grf-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node04"
      cores           = 1
      memory          = 1024
      disk_size       = "10"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.241/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-pm-srv01" = {
      vmid            = 402
      hostname        = "horus-pm-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node04"
      cores           = 2
      memory          = 2048
      disk_size       = "15"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.242/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-lok-srv01" = {
      vmid            = 403
      hostname        = "horus-lok-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node04"
      cores           = 2
      memory          = 2048
      disk_size       = "15"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.243/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-otel-srv01" = {
      vmid            = 404
      hostname        = "horus-otel-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node04"
      cores           = 1
      memory          = 1024
      disk_size       = "5"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.244/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
    "horus-s3-srv01" = {
      vmid            = 405
      hostname        = "horus-s3-srv01"
      type            = "lxc"
      target_node     = "horus-pmx-node04"
      cores           = 2
      memory          = 2048
      disk_size       = "40"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.245/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
      additional_mounts = [
        {
          mount_type   = "dedicated_volume"
          volume       = "storage-logs"
          mp           = "/data"
          storage_name = "storage-logs"
          size         = "430G"
        }
      ]
    }
    "horus-ai-srv04" = {
      vmid            = 406
      hostname        = "horus-ai-srv04"
      type            = "lxc"
      target_node     = "horus-pmx-node04"
      cores           = 4
      memory          = 4096
      disk_size       = "32"
      root_storage    = "local-lvm"
      ip_address      = "192.168.1.246/24"
      bridge          = "vmbr0"
      vlan_id         = 0
      image_source    = local.lxc_template_file_id
      feature_profile = "standard"
    }
  }

  physical_node_ram_mb = {
    "horus-pmx-node01" = 31785 # 31.04 GiB
    "horus-pmx-node02" = 31785 # 31.04 GiB
    "horus-pmx-node03" = 15953 # 15.58 GiB
    "horus-pmx-node04" = 15912 # 15.54 GiB
  }

  node01_ram_allocated_mb = sum([for w in values(local.workloads) : w.memory if w.target_node == "horus-pmx-node01"])
  node02_ram_allocated_mb = sum([for w in values(local.workloads) : w.memory if w.target_node == "horus-pmx-node02"])
  node03_ram_allocated_mb = sum([for w in values(local.workloads) : w.memory if w.target_node == "horus-pmx-node03"])
  node04_ram_allocated_mb = sum([for w in values(local.workloads) : w.memory if w.target_node == "horus-pmx-node04"])

  valid_nodes = ["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]

  workload_mount_datastores = {
    for k, w in local.workloads : k => [
      for m in try(w.additional_mounts, []) : m.storage_name
    ]
  }

  all_workload_mounts = flatten([
    for k, w in local.workloads : concat(
      [
        for m in try(w.additional_mounts, []) : {
          workload_key = k
          hostname     = w.hostname
          target_node  = w.target_node
          storage_name = m.storage_name
          volume       = m.volume
          mp           = m.mp
          mount_type   = m.mount_type
          size         = try(m.size, null)
        }
      ],
      [
        for d in try(w.additional_disks, []) : {
          workload_key = k
          hostname     = w.hostname
          target_node  = w.target_node
          storage_name = d.storage_name
          volume       = d.datastore
          mp           = d.interface
          mount_type   = try(d.mount_type, "dedicated_volume")
          size         = d.size
        }
      ]
    )
  ])

  storage_inventory = {
    "local" = {
      storage_name      = "local"
      scope             = "per_node"
      physical_owner    = "per-node (node01, node02, node03, node04)"
      type              = "dir"
      device_or_path    = "System SSD Directory"
      filesystem        = "ext4 / dir"
      export_type       = "local"
      allowed_consumers = ["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]
      purpose           = "Proxmox directory storage (local to each node)"
    }
    "local-lvm" = {
      storage_name      = "local-lvm"
      scope             = "per_node"
      physical_owner    = "per-node (node01, node02, node03, node04)"
      type              = "lvm-thin"
      device_or_path    = "System SSD LVM-thin"
      filesystem        = "raw / lvm-thin"
      export_type       = "local"
      allowed_consumers = ["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]
      purpose           = "System LVM-thin root filesystem storage for all VMs and LXCs"
    }
    "storage" = {
      storage_name      = "storage"
      scope             = "shared"
      physical_owner    = "horus-pmx-node03"
      type              = "nfs"
      device_or_path    = "/dev/sda (2 TB WDC WD20EFRX)"
      filesystem        = "ext4"
      export_type       = "nfs"
      allowed_consumers = ["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]
      purpose           = "General NAS / user & application shared files"
    }
    "storage-media" = {
      storage_name      = "storage-media"
      scope             = "shared"
      physical_owner    = "horus-pmx-node03"
      type              = "nfs"
      device_or_path    = "/dev/sdb (3 TB Seagate ST3000DM007)"
      filesystem        = "ext4"
      export_type       = "nfs"
      allowed_consumers = ["horus-pmx-node01", "horus-pmx-node02"]
      purpose           = "Media storage (JoyFilm, CasaOS media)"
    }
    "storage-work" = {
      storage_name      = "storage-work"
      scope             = "shared"
      physical_owner    = "horus-pmx-node03"
      type              = "nfs"
      device_or_path    = "/dev/sdc (1 TB Seagate ST1000DM003)"
      filesystem        = "ext4"
      export_type       = "nfs"
      allowed_consumers = ["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]
      purpose           = "Application stateful persistent data (PostgreSQL, Gitea)"
    }
    "storage-infra" = {
      storage_name      = "storage-infra"
      scope             = "shared"
      physical_owner    = "horus-pmx-node03"
      type              = "nfs"
      device_or_path    = "/dev/sdd (1 TB Toshiba MQ01ABD100)"
      filesystem        = "ext4"
      export_type       = "nfs"
      allowed_consumers = ["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]
      purpose           = "Infrastructure factory storage (ISO, LXC templates, VM/template artifacts, backups, snippets)"
    }
    "storage-ai" = {
      storage_name      = "storage-ai"
      scope             = "per_node"
      physical_owner    = "horus-pmx-node02"
      type              = "dir"
      device_or_path    = "480 GB Seagate SSD"
      filesystem        = "ext4"
      export_type       = "local"
      allowed_consumers = ["horus-pmx-node02"]
      purpose           = "Local AI models, AI datasets, AI persistent data (Mimir horus-ai-srv03)"
    }
    "storage-logs" = {
      storage_name      = "storage-logs"
      scope             = "per_node"
      physical_owner    = "horus-pmx-node04"
      type              = "dir"
      device_or_path    = "/dev/sdb (500 GB WD5000LPVT HDD)"
      filesystem        = "ext4"
      export_type       = "local"
      allowed_consumers = ["horus-pmx-node04"]
      purpose           = "Observability / monitoring data, logs & MinIO S3 backend (horus-s3-srv01)"
    }
  }
}

# 1. Placement completeness
check "placement_completeness" {
  assert {
    condition     = length(local.workloads) == 22
    error_message = "Expected exactly 22 workloads in the approved HoRus deployment scope."
  }
}

# 2. VMID uniqueness
check "vmid_uniqueness" {
  assert {
    condition     = length(distinct([for w in values(local.workloads) : w.vmid])) == 22
    error_message = "VMIDs must be unique across all 22 workloads."
  }
}

# 3. Hostname uniqueness
check "hostname_uniqueness" {
  assert {
    condition     = length(distinct(keys(local.workloads))) == 22
    error_message = "Hostnames must be unique across all 22 workloads."
  }
}

# 4. Target node validity
check "node_validity" {
  assert {
    condition     = alltrue([for w in values(local.workloads) : contains(local.valid_nodes, w.target_node)])
    error_message = "All workloads must be targeted to one of horus-pmx-node01..node04."
  }
}

# 5. Type validity
check "type_validity" {
  assert {
    condition     = alltrue([for w in values(local.workloads) : contains(["vm", "lxc"], w.type)])
    error_message = "Workload type must be either 'vm' or 'lxc'."
  }
}

# 6. Image source correctness
check "image_source_correctness" {
  assert {
    condition = alltrue([
      for w in values(local.workloads) : (
        w.type == "lxc" ? w.image_source == "storage-infra:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst" : w.image_source == "9000"
      )
    ])
    error_message = "LXC workloads must use storage-infra LXC template, and VM workloads must use Golden VM 9000."
  }
}

# 7. Root storage validity
check "root_storage_validity" {
  assert {
    condition     = alltrue([for w in values(local.workloads) : w.root_storage == "local-lvm"])
    error_message = "All workloads must use local-lvm for root filesystem."
  }
}

# 8. Storage consumer rules: storage-media (only node01, node02)
check "storage_media_consumer" {
  assert {
    condition = alltrue([
      for k, ds_list in local.workload_mount_datastores : (
        contains(ds_list, "storage-media") ? contains(["horus-pmx-node01", "horus-pmx-node02"], local.workloads[k].target_node) : true
      )
    ])
    error_message = "storage-media can only be consumed by workloads on horus-pmx-node01 or horus-pmx-node02."
  }
}

# 9. Storage consumer rules: storage-ai (only node02)
check "storage_ai_consumer" {
  assert {
    condition = alltrue([
      for k, ds_list in local.workload_mount_datastores : (
        contains(ds_list, "storage-ai") ? local.workloads[k].target_node == "horus-pmx-node02" : true
      )
    ])
    error_message = "storage-ai is local to horus-pmx-node02 and cannot be consumed by other nodes."
  }
}

# 10. Storage consumer rules: storage-logs (only node04)
check "storage_logs_consumer" {
  assert {
    condition = alltrue([
      for k, ds_list in local.workload_mount_datastores : (
        contains(ds_list, "storage-logs") ? local.workloads[k].target_node == "horus-pmx-node04" : true
      )
    ])
    error_message = "storage-logs is local to horus-pmx-node04 and cannot be consumed by other nodes."
  }
}

# 11. Workload 305 / horus-retro-srv01 absence
check "workload_305_absent" {
  assert {
    condition     = !contains(keys(local.workloads), "horus-retro-srv01") && !contains([for w in values(local.workloads) : w.vmid], 305)
    error_message = "VMID 305 (horus-retro-srv01) is excluded from the current deployment scope."
  }
}

# 12. VM image isolation
check "vm_image_isolation" {
  assert {
    condition = alltrue([
      for w in values(local.workloads) : (
        w.type == "vm" ? !endswith(w.image_source, ".tar.zst") : true
      )
    ])
    error_message = "VM workloads must not use LXC .tar.zst templates."
  }
}

# 13. LXC image isolation
check "lxc_image_isolation" {
  assert {
    condition = alltrue([
      for w in values(local.workloads) : (
        w.type == "lxc" ? w.image_source != "9000" : true
      )
    ])
    error_message = "LXC workloads must not clone VM template 9000."
  }
}

# Resource capacity check
check "resource_capacity" {
  assert {
    condition     = local.node01_ram_allocated_mb <= local.physical_node_ram_mb["horus-pmx-node01"]
    error_message = "Node01 allocated RAM exceeds physical RAM capacity."
  }
  assert {
    condition     = local.node02_ram_allocated_mb <= local.physical_node_ram_mb["horus-pmx-node02"]
    error_message = "Node02 allocated RAM exceeds physical RAM capacity."
  }
  assert {
    condition     = local.node03_ram_allocated_mb <= local.physical_node_ram_mb["horus-pmx-node03"]
    error_message = "Node03 allocated RAM exceeds physical RAM capacity."
  }
  assert {
    condition     = local.node04_ram_allocated_mb <= local.physical_node_ram_mb["horus-pmx-node04"]
    error_message = "Node04 allocated RAM exceeds physical RAM capacity."
  }
}

# 14. Generic storage inventory & mount validation
check "generic_storage_mount_validation" {
  # 1. Datastore/Storage exists in storage_inventory
  assert {
    condition     = alltrue([for m in local.all_workload_mounts : contains(keys(local.storage_inventory), m.storage_name)])
    error_message = "All mounted storage names must exist in local.storage_inventory."
  }

  # 2. Target node is an allowed consumer for the storage
  assert {
    condition     = alltrue([for m in local.all_workload_mounts : contains(local.storage_inventory[m.storage_name].allowed_consumers, m.target_node)])
    error_message = "Workload target_node must be listed in storage_inventory allowed_consumers for the requested storage."
  }

  # 3. bind_mount validation
  assert {
    condition = alltrue([
      for m in local.all_workload_mounts : (
        m.mount_type == "bind_mount" ? (
          can(regex("^/mnt/pve/", m.volume)) && m.size == null
        ) : true
      )
    ])
    error_message = "bind_mount entries must specify a valid host path starting with /mnt/pve/ for volume and omit size."
  }

  # 4. dedicated_volume validation
  assert {
    condition = alltrue([
      for m in local.all_workload_mounts : (
        m.mount_type == "dedicated_volume" ? m.size != null : true
      )
    ])
    error_message = "dedicated_volume entries must specify a non-null disk size."
  }

  # 5. Local storage isolation (local directory storage cannot be consumed cross-node)
  assert {
    condition = alltrue([
      for m in local.all_workload_mounts : (
        local.storage_inventory[m.storage_name].export_type == "local" && !can(regex(".*,.*", local.storage_inventory[m.storage_name].physical_owner)) ?
        local.storage_inventory[m.storage_name].physical_owner == m.target_node : true
      )
    ])
    error_message = "Local single-node datastores (e.g. storage-ai, storage-logs) can only be mounted on their physical owner node."
  }

  # 6. storage-media bind_mount semantics validation
  assert {
    condition = alltrue([
      for m in local.all_workload_mounts : (
        m.storage_name == "storage-media" ?
        m.mount_type == "bind_mount" &&
        m.volume == "/mnt/pve/.horus-nfs/storage-media" &&
        m.size == null
        : true
      )
    ])
    error_message = "storage-media mounts must use bind_mount semantics referencing /mnt/pve/.horus-nfs/storage-media without volume allocation."
  }

  # 7. storage bind_mount semantics validation for horus-media-srv01
  assert {
    condition = alltrue([
      for m in local.all_workload_mounts : (
        m.hostname == "horus-media-srv01" && m.storage_name == "storage" ?
        m.mount_type == "bind_mount" &&
        m.volume == "/mnt/pve/.horus-nfs/storage" &&
        m.size == null
        : true
      )
    ])
    error_message = "storage mount for horus-media-srv01 must use bind_mount referencing /mnt/pve/.horus-nfs/storage without volume allocation."
  }

  # 8. Vault 302 persistent storage on storage-work validation
  assert {
    condition     = contains([for m in local.all_workload_mounts : "${m.hostname}:${m.storage_name}"], "horus-vlt-srv01:storage-work")
    error_message = "horus-vlt-srv01 (Vault) must have persistent storage configured on storage-work."
  }
}