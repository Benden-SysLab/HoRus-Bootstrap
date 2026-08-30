terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

locals {
  # Ищем ID шаблона по имени ноды, если не нашли — берем дефолт
  chosen_template_id = var.clone_template_id
}

# Основной блок развертывания ВМ
resource "proxmox_virtual_environment_vm" "kvm_node" {
  node_name = var.target_node
  vm_id     = var.vmid
  name      = var.hostname

  # Включаем поддержку агента со стороны Proxmox
  agent {
    enabled = true
  }

  # Клонирование Golden VM с Factory Node.
  # Целевое хранилище задается ниже в disk.datastore_id.
  clone {
    vm_id     = local.chosen_template_id
    node_name = var.factory_node
    full      = true
  }

  # CPU и память
  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  # Корневой диск
  # Именно здесь указывается локальное хранилище целевой ноды.
  disk {
    datastore_id = var.root_storage
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = "raw"
  }

  # Дополнительные диски
  # Например, persistent data на storage-work для Vault.
  dynamic "disk" {
    for_each = var.additional_disks

    content {
      datastore_id = disk.value.datastore
      interface    = disk.value.interface
      size         = disk.value.size
      file_format  = "raw"
    }
  }

  # Сеть
  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  # Cloud-Init
  initialization {
    type         = "nocloud"
    datastore_id = var.root_storage

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
      keys = [
        can(file(var.ssh_public_key))
        ? trimspace(file(var.ssh_public_key))
        : trimspace(var.ssh_public_key)
      ]
    }
  }
}