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
  # ВНИМАНИЕ: Проверь соответствие! 
  node_templates = {
    "horus-pmx-srv01" = 9000
    "horus-pmx-srv02" = 9001
    "horus-pmx-srv03" = 9002
  }

  # Ищем ID шаблона по имени ноды, если не нашли — берем дефолт
  chosen_template_id = lookup(local.node_templates, var.target_node, var.clone_template_id)
}

locals {
  # Карта: нода -> имя хранилища на ней
  # Это гарантирует, что ВМ на ноде 01 всегда будет использовать быстрый/большой диск этой ноды
  node_storage_map = {
    "horus-pmx-srv01" = "storage"      # или тот ID, который ты создал в GUI
    "horus-pmx-srv02" = "data-ai"      # твой диск на 447G
    "horus-pmx-srv03" = "data"         # твой диск на 465G
  }

  # Фиксированный MAC-адрес: если не передан явно в var.mac_address,
  # генерируется детерминированно на основе VMID (например, 203 -> BC:24:11:00:02:03)
  final_mac_address = var.mac_address != null ? var.mac_address : format("BC:24:11:00:%02d:%02d", floor(var.vmid / 100), var.vmid % 100)
}

# 1. Твой основной блок развертывания ВМ
resource "proxmox_virtual_environment_vm" "kvm_node" {
  node_name = var.target_node
  vm_id     = var.vmid
  name      = var.hostname

  # ---> ДОБАВЛЕНО: Включаем поддержку агента со стороны Proxmox <---
  agent {
    enabled = true
  }

  # Настройка клонирования из шаблона
  clone {
    vm_id = local.chosen_template_id # <--- ИСПРАВЛЕНО: теперь берем значение из locals!
    full  = true
  }

  # CPU и память
  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  # Диск
  disk {
    # Мы обращаемся к карте locals, используя имя ноды как ключ
    datastore_id = lookup(local.node_storage_map, var.target_node, "local")
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = var.disk_file_format
  }

  # Сеть
  network_device {
    bridge      = "vmbr0"
    vlan_id     = var.vlan_id
    mac_address = local.final_mac_address
  }

  # Инициализация (настройка пользователя, сети и SSH)
  initialization {
    type         = "nocloud"
    datastore_id = "infra"
    
    # Блок dns идет первым внутри initialization:
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
      username = "root"
      password = var.root_password
      keys     = [can(file(var.ssh_public_key)) ? trimspace(file(var.ssh_public_key)) : trimspace(var.ssh_public_key)]
    }
  }
}

# Пауза (лаг) для того, чтобы ВМ успела запуститься и инициализировать qemu-guest-agent/сеть
resource "time_sleep" "wait_for_vm" {
  create_duration = "45s"

  depends_on = [
    proxmox_virtual_environment_vm.kvm_node
  ]
}