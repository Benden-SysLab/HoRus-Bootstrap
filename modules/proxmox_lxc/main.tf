terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

locals {
  node_storage_map = {
    "horus-pmx-srv01" = "storage"
    "horus-pmx-srv02" = "data-ai"
    "horus-pmx-srv03" = "data"
  }

  # Фиксированный MAC-адрес: если не передан явно в var.mac_address,
  # генерируется детерминированно на основе VMID (например, 205 -> BC:24:11:00:02:05)
  final_mac_address = var.mac_address != null ? var.mac_address : format("BC:24:11:00:%02d:%02d", floor(var.vmid / 100), var.vmid % 100)
}

resource "proxmox_virtual_environment_container" "lxc_node" {
  node_name    = var.target_node
  vm_id        = var.vmid
  unprivileged = var.unprivileged
  tags         = var.tags
  protection   = var.protection

  startup {
    order      = var.startup.order
    up_delay   = var.startup.up_delay
    down_delay = var.startup.down_delay
  }

  features {
    nesting = var.container_features.nesting
    keyctl  = var.container_features.keyctl
    fuse    = var.container_features.fuse
    mount   = var.container_features.mount
    mknod   = var.container_features.mknod
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

    user_account {
      password = var.root_password
      keys     = [can(file(var.ssh_public_key)) ? trimspace(file(var.ssh_public_key)) : trimspace(var.ssh_public_key)]
    }
  }

  console {
    type = "shell"
  }

  operating_system {
    template_file_id = var.ostemplate
    type             = "debian"
  }

  cpu {
    cores  = var.cores
    units  = var.cpu_units
    limit  = var.cpu_limit
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.rootfs_disk.datastore_id != "local" ? var.rootfs_disk.datastore_id : lookup(local.node_storage_map, var.target_node, "local")
    size         = var.rootfs_disk.size
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    vlan_id     = var.vlan_id
    mac_address = local.final_mac_address
  }

  dynamic "mount_point" {
    for_each = var.additional_mounts
    content {
      volume = mount_point.value.datastore
      path   = mount_point.value.mp
      size   = mount_point.value.size
    }
  }
}

# Пауза (лаг) для того, чтобы контейнер успел запуститься и инициализировать сеть/настройки
resource "time_sleep" "wait_for_container" {
  create_duration = "30s"

  depends_on = [
    proxmox_virtual_environment_container.lxc_node
  ]
}