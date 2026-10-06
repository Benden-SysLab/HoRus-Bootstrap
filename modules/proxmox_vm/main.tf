terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "kvm_node" {
  node_name = var.target_node
  vm_id     = var.vmid
  name      = var.hostname
  migrate   = true
  started   = true
  on_boot   = true

  purge_on_destroy                     = true
  delete_unreferenced_disks_on_destroy = true

  agent {
    enabled = true
  }

  clone {
    vm_id        = var.clone_template_id
    node_name    = var.factory_node
    datastore_id = var.root_storage
    full         = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.root_storage
    interface    = "scsi0"
    size         = tonumber(var.disk_size)
    file_format  = "raw"
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  # Golden 9000 already contains the approved users and SSH keys. Cloud-Init
  # owns only network/DNS here and does not overwrite that security baseline.
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
  }
}
