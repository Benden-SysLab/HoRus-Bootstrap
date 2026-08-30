terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

locals {
  proxmox_node_ip_map = {
    "horus-pmx-node01" = "192.168.1.210"
    "horus-pmx-node02" = "192.168.1.220"
    "horus-pmx-node03" = "192.168.1.230"
    "horus-pmx-node04" = "192.168.1.240"
  }

  resolved_proxmox_host = lookup(local.proxmox_node_ip_map, var.target_node, "192.168.1.210")

  feature_profiles = {
    standard = { nesting = true, keyctl = true, fuse = false, mount = [], mknod = false }
    docker   = { nesting = true, keyctl = true, fuse = true, mount = [], mknod = true }
    system   = { nesting = true, keyctl = true, fuse = false, mount = [], mknod = false }
    storage  = { nesting = true, keyctl = true, fuse = true, mount = ["nfs", "cifs"], mknod = false }
  }

  final_features = lookup(local.feature_profiles, var.feature_profile, local.feature_profiles["standard"])
}

resource "proxmox_virtual_environment_container" "lxc_node" {
  node_name    = var.target_node
  vm_id        = var.vmid
  unprivileged = true

  operating_system {
    template_file_id = var.ostemplate
    type             = "debian"
  }

  features {
    nesting = local.final_features.nesting
    keyctl  = local.final_features.keyctl
    fuse    = local.final_features.fuse
    mount   = local.final_features.mount
    mknod   = local.final_features.mknod
  }

  initialization {
    hostname = var.hostname

    # Блок dns лежит прямо внутри initialization, РЯДОМ с ip_config
    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      password = var.root_password
      keys     = [can(file(var.ssh_public_key)) ? trimspace(file(var.ssh_public_key)) : trimspace(var.ssh_public_key)]
    }
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
    size         = var.disk_size
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  dynamic "mount_point" {
    for_each = var.additional_mounts
    content {
      volume = mount_point.value.volume
      path   = mount_point.value.mp
      size   = mount_point.value.mount_type == "bind_mount" ? null : mount_point.value.size
    }
  }
}