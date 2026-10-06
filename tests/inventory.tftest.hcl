variables {
  pmx_api_url            = "https://192.0.2.10:8006/api2/json"
  pmx_api_token          = "test@pam!terraform=00000000-0000-0000-0000-000000000000"
  bootstrap_ssh_key_path = "C:/example/keys/proxmox_ed25519"

  environment = {
    management = {
      cidr    = "192.0.2.0/24"
      gateway = "192.0.2.1"
      nodes = {
        horus-pmx-node01 = "192.0.2.11"
        horus-pmx-node02 = "192.0.2.12"
        horus-pmx-node03 = "192.0.2.13"
        horus-pmx-node04 = "192.0.2.14"
        example-extra    = "192.0.2.15"
      }
    }
    vlan_networks = {
      "101" = { cidr = "198.51.100.0/28", gateway = "198.51.100.1" }
      "110" = { cidr = "198.51.100.16/28", gateway = "198.51.100.17" }
      "120" = { cidr = "198.51.100.32/28", gateway = "198.51.100.33" }
      "130" = { cidr = "198.51.100.48/28", gateway = "198.51.100.49" }
      "140" = { cidr = "198.51.100.64/28", gateway = "198.51.100.65" }
      "150" = { cidr = "198.51.100.80/28", gateway = "198.51.100.81" }
      "160" = { cidr = "198.51.100.96/28", gateway = "198.51.100.97" }
      "170" = { cidr = "198.51.100.112/28", gateway = "198.51.100.113" }
      "180" = { cidr = "198.51.100.128/28", gateway = "198.51.100.129" }
      "999" = { cidr = "203.0.113.0/28", gateway = "203.0.113.1" }
    }
    workload_ips = {
      horus-lb-srv01    = "198.51.100.114/28"
      horus-agent-srv01 = "198.51.100.2/28"
      horus-jnk-srv01   = "198.51.100.3/28"
      horus-ai-srv01    = "198.51.100.82/28"
      horus-db-srv01    = "198.51.100.83/28"
      horus-media-srv01 = "198.51.100.4/28"
      horus-k8sw-srv01  = "198.51.100.130/28"
      horus-ans-srv01   = "198.51.100.5/28"
      horus-ai-srv02    = "198.51.100.98/28"
      horus-db-srv02    = "198.51.100.99/28"
      horus-vec-srv01   = "198.51.100.100/28"
      horus-cache-srv01 = "198.51.100.101/28"
      horus-iam-srv01   = "198.51.100.6/28"
      horus-media-srv02 = "198.51.100.7/28"
      horus-k8sw-srv02  = "198.51.100.131/28"
      horus-k8sc-srv01  = "198.51.100.132/28"
      horus-db-srv03    = "198.51.100.8/28"
      horus-vlt-srv01   = "198.51.100.9/28"
      horus-wiki-srv01  = "198.51.100.10/28"
      horus-git-srv01   = "198.51.100.11/28"
      horus-work-srv01  = "198.51.100.12/28"
      horus-reg-srv01   = "198.51.100.13/28"
      horus-grf-srv01   = "198.51.100.84/28"
      horus-pm-srv01    = "198.51.100.85/28"
      horus-lok-srv01   = "198.51.100.86/28"
      horus-otel-srv01  = "198.51.100.87/28"
      horus-s3-srv01    = "198.51.100.88/28"
      horus-ai-srv03    = "198.51.100.89/28"
      example-extra     = "203.0.113.2/28"
    }
    dns_servers = ["198.51.100.1", "203.0.113.53"]
    storage_paths = {
      guardian-data = "/srv/example/guardian-data"
      mimir-data    = "/srv/example/mimir-data"
      infra         = "/srv/example/infra"
      artifacts     = "/srv/example/artifacts"
      logs          = "/srv/example/logs"
      media         = "/srv/example/media"
      example-extra = "/srv/example/extra"
    }
    guest_paths = {
      artifacts-shared   = "/data/example/artifacts"
      guardian-data      = "/data/example/guardian-data"
      media              = "/data/example/media"
      mimir-data         = "/data/example/mimir-data"
      mimir-postgres     = "/data/example/mimir-data/postgres"
      mimir-vectors      = "/data/example/mimir-data/vectors"
      infra-postgres     = "/data/example/infra/postgres"
      infra-wiki         = "/data/example/infra/wiki"
      infra-gitea        = "/data/example/infra/gitea"
      artifacts-registry = "/data/example/artifacts/registry"
      logs               = "/data/example/logs"
      example-extra      = "/data/example/extra"
    }
    nfs = {
      media         = { server = "192.0.2.13", export = "/srv/example/media" }
      artifacts     = { server = "192.0.2.13", export = "/srv/example/artifacts/builds" }
      example-extra = { server = "192.0.2.15", export = "/srv/example/extra" }
    }
  }
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
  assert {
    condition     = length(local.nodes) == 4 && length(local.vlans) == 9 && length(local.workloads) == 28
    error_message = "Extra environment mappings must not create topology objects."
  }
}
