terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

locals {
  feature_profiles = {
    standard = { nesting = true, keyctl = true, fuse = false, mount = [], mknod = false }
    docker   = { nesting = true, keyctl = true, fuse = true, mount = [], mknod = true }
    system   = { nesting = true, keyctl = true, fuse = false, mount = [], mknod = false }
    storage  = { nesting = true, keyctl = true, fuse = true, mount = ["nfs", "cifs"], mknod = false }
  }
  final_features = lookup(local.feature_profiles, var.feature_profile, local.feature_profiles.standard)
}

resource "proxmox_virtual_environment_container" "lxc_node" {
  # Proxmox permits this cross-node clone only to shared storage. The CT is
  # cloned directly on its final node; the completion barrier then moves only
  # rootfs from storage-infra to that node's local-lvm and starts the CT.
  node_name     = var.target_node
  vm_id         = var.vmid
  unprivileged  = true
  started       = false
  start_on_boot = true

  purge_on_destroy                     = true
  delete_unreferenced_disks_on_destroy = true
  timeout_delete                       = 600

  lifecycle {
    # The placement helper owns only runtime start and the final rootfs
    # datastore/size because provider 0.115.0 cannot move an LXC rootfs.
    # Everything else, including node_name and clone identity, stays managed.
    ignore_changes = [
      started,
      disk[0].datastore_id,
      disk[0].size,
    ]
  }

  clone {
    vm_id        = var.clone_template_id
    node_name    = var.clone_node
    datastore_id = var.clone_storage
    full         = true
  }

  initialization {
    hostname = var.hostname

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }

  features {
    nesting = local.final_features.nesting
    keyctl  = local.final_features.keyctl
    fuse    = local.final_features.fuse
    mount   = local.final_features.mount
    mknod   = local.final_features.mknod
  }

  console {
    type = "shell"
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.root_storage
    size         = tonumber(var.disk_size)
  }

  dynamic "mount_point" {
    for_each = var.private_mounts
    content {
      volume = mount_point.value.datastore_id
      # PVE serializes a zero-sized directory volume as 0T. Provider 0.115.0
      # stores that API string verbatim and marks size ForceNew, so use the
      # read-back representation at the provider boundary to avoid drift.
      size   = mount_point.value.size == "0" ? "0T" : mount_point.value.size
      path   = mount_point.value.path
      backup = true
    }
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }
}
